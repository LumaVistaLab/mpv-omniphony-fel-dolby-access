-- Headless probe of the actual built-in video/audio selector labels.
-- Run mpv with --no-config --load-console=no --vo=null --ao=null --pause
-- and --script=<this file>. Its basename must remain console.lua so that
-- mp.input delivers the built-in selector's get-input requests here.
-- Reports labels and numeric track metadata; never prints media URLs or cookies.
local utils = require 'mp.utils'
local result = {video = {}, audio = {}, tracks = {}}
local stage = 'video'

mp.register_script_message('get-input', function(json)
    local request = utils.parse_json(json)
    if not request or request.client_name ~= 'select' then return end
    result[stage] = request.items
    mp.commandv('script-message-to', request.client_name,
                request.handler_id, 'closed', '[]')
    if stage == 'video' then
        stage = 'audio'
        mp.commandv('script-binding', 'select/select-aid')
    else
        print('FORMAT_MENU=' .. utils.format_json(result))
        mp.commandv('quit')
    end
end)

mp.register_event('file-loaded', function()
    for _, track in ipairs(mp.get_property_native('track-list', {})) do
        result.tracks[#result.tracks + 1] = {
            id = track.id, type = track.type, title = track.title,
            selected = track.selected, codec = track.codec,
            demux_fps = track['demux-fps'],
            format_fps = track['format-fps'],
            advertised_bitrate = track['hls-bitrate'],
            demux_bitrate = track['demux-bitrate'],
        }
    end
    mp.commandv('script-binding', 'select/select-vid')
end)

mp.add_timeout(45, function()
    mp.msg.error('Timed out waiting for the native format selectors')
    mp.commandv('quit', 3)
end)
