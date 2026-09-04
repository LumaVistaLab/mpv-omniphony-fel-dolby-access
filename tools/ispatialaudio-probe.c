#define COBJMACROS
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <spatialaudioclient.h>
#include <propvarutil.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Keep the probe buildable with older uuid.lib revisions. These values are the
// SDK-declared interface/class UUIDs, scoped locally to avoid link dependencies.
static const GUID probe_clsid_mmdevice_enumerator =
    {0xbcde0395, 0xe52f, 0x467c, {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}};
static const GUID probe_iid_immdevice_enumerator =
    {0xa95664d2, 0x9614, 0x4f35, {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}};
static const GUID probe_iid_spatial_audio_client =
    {0xbbf8e066, 0xaaaa, 0x49be, {0x9a, 0x4d, 0xfd, 0x2a, 0x85, 0x8e, 0xa2, 0x7f}};
static const GUID probe_iid_spatial_render_stream =
    {0xbab5f473, 0xb423, 0x477b, {0x85, 0xf5, 0xb5, 0xa3, 0x32, 0xa0, 0x41, 0x53}};

static const AudioObjectType bed_7_1_4[] = {
    AudioObjectType_FrontLeft,
    AudioObjectType_FrontRight,
    AudioObjectType_FrontCenter,
    AudioObjectType_LowFrequency,
    AudioObjectType_BackLeft,
    AudioObjectType_BackRight,
    AudioObjectType_SideLeft,
    AudioObjectType_SideRight,
    AudioObjectType_TopFrontLeft,
    AudioObjectType_TopFrontRight,
    AudioObjectType_TopBackLeft,
    AudioObjectType_TopBackRight,
};

static AudioObjectType bed_mask(void)
{
    AudioObjectType mask = AudioObjectType_None;
    for (size_t i = 0; i < _countof(bed_7_1_4); i++)
        mask = (AudioObjectType)(mask | bed_7_1_4[i]);
    return mask;
}

static void print_hr(const wchar_t *what, HRESULT hr)
{
    wchar_t *message = NULL;
    FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER |
                   FORMAT_MESSAGE_FROM_SYSTEM |
                   FORMAT_MESSAGE_IGNORE_INSERTS,
                   NULL, (DWORD)hr, 0, (wchar_t *)&message, 0, NULL);
    fwprintf(stderr, L"%ls failed: 0x%08lX%ls%ls\n", what,
             (unsigned long)hr, message ? L" - " : L"",
             message ? message : L"");
    if (message)
        LocalFree(message);
}

static WAVEFORMATEX *choose_object_format(IAudioFormatEnumerator *formats)
{
    UINT32 count = 0;
    if (FAILED(IAudioFormatEnumerator_GetCount(formats, &count)))
        return NULL;

    WAVEFORMATEX *fallback = NULL;
    for (UINT32 i = 0; i < count; i++) {
        WAVEFORMATEX *format = NULL;
        if (FAILED(IAudioFormatEnumerator_GetFormat(formats, i, &format)) || !format)
            continue;

        wprintf(L"object format[%u]: %lu Hz, %u channel(s), %u-bit, tag 0x%04X\n",
                i, format->nSamplesPerSec, format->nChannels,
                format->wBitsPerSample, format->wFormatTag);

        if (!fallback)
            fallback = format;
        else if (format->nChannels == 1 && format->nSamplesPerSec == 48000 &&
                 format->wBitsPerSample == 32) {
            CoTaskMemFree(fallback);
            return format;
        } else {
            CoTaskMemFree(format);
        }
    }
    return fallback;
}

int wmain(void)
{
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(hr)) {
        print_hr(L"CoInitializeEx", hr);
        return 1;
    }

    int result = 1;
    IMMDeviceEnumerator *device_enumerator = NULL;
    IMMDevice *device = NULL;
    IPropertyStore *properties = NULL;
    ISpatialAudioClient *client = NULL;
    IAudioFormatEnumerator *formats = NULL;
    ISpatialAudioObjectRenderStream *stream = NULL;
    ISpatialAudioObject *objects[_countof(bed_7_1_4)] = {0};
    WAVEFORMATEX *object_format = NULL;
    HANDLE event = NULL;
    PROPVARIANT friendly_name;
    PropVariantInit(&friendly_name);

    hr = CoCreateInstance(&probe_clsid_mmdevice_enumerator, NULL,
                          CLSCTX_INPROC_SERVER,
                          &probe_iid_immdevice_enumerator,
                          (void **)&device_enumerator);
    if (FAILED(hr)) {
        print_hr(L"CoCreateInstance(MMDeviceEnumerator)", hr);
        goto done;
    }

    hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(
        device_enumerator, eRender, eMultimedia, &device);
    if (FAILED(hr)) {
        print_hr(L"GetDefaultAudioEndpoint", hr);
        goto done;
    }

    hr = IMMDevice_OpenPropertyStore(device, STGM_READ, &properties);
    if (SUCCEEDED(hr))
        hr = IPropertyStore_GetValue(properties, &PKEY_Device_FriendlyName,
                                     &friendly_name);
    if (SUCCEEDED(hr) && friendly_name.vt == VT_LPWSTR)
        wprintf(L"default multimedia endpoint: %ls\n", friendly_name.pwszVal);

    hr = IMMDevice_Activate(device, &probe_iid_spatial_audio_client,
                            CLSCTX_INPROC_SERVER, NULL, (void **)&client);
    if (FAILED(hr)) {
        print_hr(L"Activate(ISpatialAudioClient)", hr);
        goto done;
    }

    AudioObjectType native_mask = AudioObjectType_None;
    hr = ISpatialAudioClient_GetNativeStaticObjectTypeMask(client, &native_mask);
    if (FAILED(hr)) {
        print_hr(L"GetNativeStaticObjectTypeMask", hr);
        goto done;
    }

    UINT32 max_dynamic = 0;
    hr = ISpatialAudioClient_GetMaxDynamicObjectCount(client, &max_dynamic);
    if (FAILED(hr)) {
        print_hr(L"GetMaxDynamicObjectCount", hr);
        goto done;
    }
    wprintf(L"native static mask: 0x%08X; max dynamic objects: %u\n",
            (unsigned)native_mask, max_dynamic);

    AudioObjectType required_mask = bed_mask();
    if ((native_mask & required_mask) != required_mask) {
        fwprintf(stderr,
                 L"7.1.4 static bed unavailable: required 0x%08X, missing 0x%08X\n",
                 (unsigned)required_mask,
                 (unsigned)(required_mask & ~native_mask));
        goto done;
    }

    hr = ISpatialAudioClient_GetSupportedAudioObjectFormatEnumerator(client,
                                                                      &formats);
    if (FAILED(hr)) {
        print_hr(L"GetSupportedAudioObjectFormatEnumerator", hr);
        goto done;
    }
    object_format = choose_object_format(formats);
    if (!object_format) {
        fwprintf(stderr, L"No spatial audio object format was reported.\n");
        goto done;
    }

    UINT32 max_frames = 0;
    hr = ISpatialAudioClient_GetMaxFrameCount(client, object_format, &max_frames);
    if (FAILED(hr)) {
        print_hr(L"GetMaxFrameCount", hr);
        goto done;
    }
    wprintf(L"selected object format: %lu Hz, %u-bit; max frame count: %u\n",
            object_format->nSamplesPerSec, object_format->wBitsPerSample,
            max_frames);

    event = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!event) {
        print_hr(L"CreateEvent", HRESULT_FROM_WIN32(GetLastError()));
        goto done;
    }

    SpatialAudioObjectRenderStreamActivationParams stream_params = {
        .ObjectFormat = object_format,
        .StaticObjectTypeMask = required_mask,
        .MinDynamicObjectCount = 0,
        .MaxDynamicObjectCount = 0,
        .Category = AudioCategory_Movie,
        .EventHandle = event,
        .NotifyObject = NULL,
    };
    PROPVARIANT activation;
    PropVariantInit(&activation);
    activation.vt = VT_BLOB;
    activation.blob.cbSize = sizeof(stream_params);
    activation.blob.pBlobData = (BYTE *)&stream_params;

    hr = ISpatialAudioClient_ActivateSpatialAudioStream(
        client, &activation, &probe_iid_spatial_render_stream,
        (void **)&stream);
    if (FAILED(hr)) {
        print_hr(L"ActivateSpatialAudioStream(7.1.4)", hr);
        goto done;
    }

    for (size_t i = 0; i < _countof(objects); i++) {
        hr = ISpatialAudioObjectRenderStream_ActivateSpatialAudioObject(
            stream, bed_7_1_4[i], &objects[i]);
        if (FAILED(hr)) {
            print_hr(L"ActivateSpatialAudioObject", hr);
            goto done;
        }
    }

    hr = ISpatialAudioObjectRenderStream_Start(stream);
    if (FAILED(hr)) {
        print_hr(L"Spatial stream Start", hr);
        goto done;
    }

    if (WaitForSingleObject(event, 2000) != WAIT_OBJECT_0) {
        fwprintf(stderr, L"Timed out waiting for the spatial render quantum.\n");
        ISpatialAudioObjectRenderStream_Stop(stream);
        goto done;
    }

    UINT32 dynamic_count = 0;
    UINT32 frames = 0;
    hr = ISpatialAudioObjectRenderStream_BeginUpdatingAudioObjects(
        stream, &dynamic_count, &frames);
    if (FAILED(hr)) {
        print_hr(L"BeginUpdatingAudioObjects", hr);
        ISpatialAudioObjectRenderStream_Stop(stream);
        goto done;
    }

    for (size_t i = 0; i < _countof(objects); i++) {
        BYTE *buffer = NULL;
        UINT32 bytes = 0;
        hr = ISpatialAudioObject_GetBuffer(objects[i], &buffer, &bytes);
        if (FAILED(hr)) {
            print_hr(L"Spatial object GetBuffer", hr);
            break;
        }
        memset(buffer, 0, bytes);
    }
    HRESULT end_hr = ISpatialAudioObjectRenderStream_EndUpdatingAudioObjects(stream);
    ISpatialAudioObjectRenderStream_Stop(stream);
    if (FAILED(hr) || FAILED(end_hr)) {
        if (FAILED(end_hr))
            print_hr(L"EndUpdatingAudioObjects", end_hr);
        goto done;
    }

    wprintf(L"SUCCESS: the default endpoint accepted and rendered one silent 7.1.4 spatial quantum (%u frames).\n",
            frames);
    result = 0;

done:
    for (size_t i = 0; i < _countof(objects); i++)
        if (objects[i])
            ISpatialAudioObject_Release(objects[i]);
    if (stream)
        ISpatialAudioObjectRenderStream_Release(stream);
    if (event)
        CloseHandle(event);
    if (object_format)
        CoTaskMemFree(object_format);
    if (formats)
        IAudioFormatEnumerator_Release(formats);
    if (client)
        ISpatialAudioClient_Release(client);
    PropVariantClear(&friendly_name);
    if (properties)
        IPropertyStore_Release(properties);
    if (device)
        IMMDevice_Release(device);
    if (device_enumerator)
        IMMDeviceEnumerator_Release(device_enumerator);
    CoUninitialize();
    return result;
}
