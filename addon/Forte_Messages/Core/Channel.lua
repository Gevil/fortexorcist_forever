-- addon/Forte_Messages/Core/Channel.lua
-- The Self-Message renderer. The source search the task asked for, with its
-- answer: the original has NO raid-warning-style frame and NO custom message
-- window at all. A Self Message is a coloured line in the DEFAULT chat frame:
--
--   * `FW:Show(msg, r, g, b, a)` is one line:
--     `DEFAULT_CHAT_FRAME:AddMessage(tostring(msg), r, g, b, a)`
--     (/tmp/fxref/Forte_Core/Forte_Core.lua:559);
--   * the module's own law says it in words: "This allows you to display
--     useful messages to yourself. They are shown in your 'default' chat
--     frame." (/tmp/fxref/Forte_Core/Localization.lua:279, :2271);
--   * every Self-Message option row in the original is a message COLOUR row
--     on the chat line (SoulstoneMsgColor Forte_Soulstone.lua:672,
--     TimerResistsColor Forte_Timer.lua:3295), and the announce sites pass
--     the colour through `FW:Show(..., unpack(FW.Settings.<Color>))`
--     (Forte_Soulstone.lua:369-374, :405-415).
--
-- DEFAULT_CHAT_FRAME + AddMessage are live on Forever: the shipped Blizzard
-- UI uses the exact call on this interface (Blizzard_ChatBase/
-- FloatingChatFrame.lua:354 binds DEFAULT_CHAT_FRAME = ChatFrame1;
-- ChatFrameUtilOverrides.lua (Camelot) :8/:15/:24 AddMessage(text,r,g,b,id)).
-- The call is pcall'd and degrades to FX.Print, so a chat-less boot costs
-- the colour, not the message.
--
-- The optional ON-SCREEN banner is the deliberate NEW half (UI/Banner.lua):
-- the original ships no on-screen self-message, the task asks for a
-- configurable on-screen message with a per-event duration, and the owner
-- ruling is "build what we actually need, label what is new". The pages say
-- so in their tips.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Messages = FX.Messages or {}

local Channel = {}
FX.Messages.Channel = Channel

Channel.counts = { chat = 0, printed = 0 }

--- The original's FW:Show, colour included. Returns "chat" | "printed".
function Channel:Show(msg, colour)
    local text = tostring(msg)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        local c = type(colour) == "table" and colour or { 1, 1, 1, 1 }
        local ok = pcall(frame.AddMessage, frame, text,
            tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1)
        if ok then
            self.counts.chat = self.counts.chat + 1
            return "chat"
        end
    end
    if FX.Print then
        pcall(FX.Print, text)
        self.counts.printed = self.counts.printed + 1
    end
    return "printed"
end

--- Fill a user template safely. Extra format arguments are ignored by
--- string.format, so one call covers the one-%s and the two-%s rows; a
--- template that cannot format (a stray %q the user typed, a %<nil>)
--- degrades to the raw template text -- a message never eats an event.
function Channel.format(fmt, a1, a2)
    if type(fmt) ~= "string" or fmt == "" then return tostring(a1) end
    local ok, out = pcall(string.format, fmt, a1, a2)
    if ok and type(out) == "string" then return out end
    return fmt
end
