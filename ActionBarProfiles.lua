-- ActionBarProfiles.lua（WoW 1.12 乌龟服 / WoW 3.3.5 WotLK 双版本）
-- 纯手动版：只做"保存当前动作条 / 加载配置"，不监听动作条改动、不自动保存、不写动作条数据到存档。
-- 作者：Sunelgy在原作者基础上优化，武藤纯子酱修复宏逻辑

-- ===== 客户端版本探测 =====
-- 同一份代码同时跑 1.12（乌龟服）和 3.3.5（WotLK）：GetActionInfo 是 2.0+ 才有的函数，
-- 拿它当"新客户端"的特征最可靠；取不到时再用 GetBuildInfo 的版本号兜底（1.12.1 vs 3.3.5）。
local function ABP_DetectModern()
    if type(GetActionInfo) == "function" then return true end
    local ver = GetBuildInfo and GetBuildInfo()
    local major = ver and tonumber(string.match(ver, "^(%d+)")) or 0
    return major >= 2
end

-- 全局状态与常量定义
local ABP_PlayerName = nil -- 当前角色标识：角色名 of 服务器名
local MAX_ACTIONS = 144 -- 1.12（乌龟服）的最大动作槽位
-- 3.3.5 的玩家动作槽只有 1-120（本机 3.3.5 的 Bartender4 按 10 条 bar x 12 生成槽号，可验证）；
-- 121 以上属于宠物/载具等特殊条，必须排除：否则宠物技能会被当成玩家技能写进档案，
-- 而且给 PlaceAction 传非法槽号有崩客户端风险（官方文档明确警告过）。
local WOTLK_MAX_ACTIONS = 120
local ABP_IS_MODERN = ABP_DetectModern() -- 是否 2.0+ 客户端（3.3.5 为 true，1.12 为 false）
local ABP_MAX_SLOTS = ABP_IS_MODERN and WOTLK_MAX_ACTIONS or MAX_ACTIONS
local ABP_DebugLevel = 0 -- 诊断输出级别：0=关，1=打印扫描/比对结果
-- 每个槽位"上次扫描"的分类结果：给加载时的"这个技能/物品其实已经在位"判断用
local ABP_SlotKind = {}
local ABP_SlotName = {}
local ABP_SlotRank = {}
local ABP_SlotTexture = {}

-- 加载结果自检：加载后等动作条稳定几秒，再扫一遍当前动作条与存档逐槽比对
local ABP_VerifyAt = nil
local ABP_VerifyProfile = nil

-- 斜杠命令关键字（中文）
local CMD_SAVE   = "保存"
local CMD_LOAD   = "加载"
local CMD_REMOVE = "删除"
local CMD_LIST   = "列表"
local CMD_CHECK  = "对比"
local CMD_EXPORT = "导出"
local CMD_IMPORT = "导入"
local CMD_DEBUG  = "debug"

-- 判断表中是否有元素（用于空配置检测）
local function hasElements(T)
    if type(T) ~= "table" then return 0 end
    for _ in pairs(T) do
        return 1
    end
    return 0
end

-- 安全读取工具 Tooltip 第一行文本，返回 (左文本, 右文本)
local function ABP_GetTooltipLine1()
    local left, right = nil, nil
    if ABP_TooltipTextLeft1 and ABP_TooltipTextLeft1:IsShown() then
        left = ABP_TooltipTextLeft1:GetText()
    end
    if ABP_TooltipTextRight1 and ABP_TooltipTextRight1:IsShown() then
        right = ABP_TooltipTextRight1:GetText()
    end
    return left, right
end

-- 组合"技能名 + 等级"作为唯一键（等级为空时仅用技能名）
local function ABP_ComposeSpellKey(name, rankText)
    if not name or name == "" then return nil end
    if rankText and rankText ~= "" then
        return name .. " " .. rankText
    end
    return name
end

-- 向默认聊天框输出消息
local function ABP_Msg(msg)
    if DEFAULT_CHAT_FRAME and msg then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

-- 诊断输出：级别 1 起生效（/abprofile debug 打开）
local function ABP_Dbg(msg)
    if ABP_DebugLevel >= 1 and DEFAULT_CHAT_FRAME and msg then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33aaff[ABP调试]|r " .. msg)
    end
end





-- 光标上是否正拿着东西（玩家在拖拽/放置技能、物品或宏）
local function ABP_CursorBusy()
    if CursorHasItem and CursorHasItem() then return true end
    if CursorHasSpell and CursorHasSpell() then return true end
    if CursorHasMacro and CursorHasMacro() then return true end
    return false
end

-- 战斗状态：3.3.5 起动作条的拾取/放置类 API 是 #nocombat 限制函数（PickupAction 自 2.2 起受限），
-- 战斗中调用会被客户端直接拒绝；1.12 没有 InCombatLockdown，这里恒为 false，旧行为完全不变。
local function ABP_InCombat()
    if InCombatLockdown then return InCombatLockdown() end
    return false
end

-- 战斗中被推迟的加载：记下配置名，脱战后自动补做（仅新客户端会注册 PLAYER_REGEN_ENABLED）
local ABP_PendingLoad = nil
local function ABP_QueueLoad(profileName)
    ABP_PendingLoad = profileName
    ABP_Msg("|cffffcc00[ABP]|r 战斗中不能改动作条，已记下配置 \"" .. profileName .. "\"，脱战后自动加载.")
end

-- 取弹窗里的输入框：1.12 回调传进来的是"确定按钮"（父级才是弹窗），3.3.5 传进来的是弹窗本身；
-- 输入框名字固定是 "<弹窗名>EditBox"。两种情况都兜住，取不到就返回 nil（不报错）。
local function ABP_GetPopupEditBox(self)
    local frame = self or this
    if not frame then return nil end
    local popup = frame
    if popup.GetObjectType and popup:GetObjectType() == "Button" then
        popup = popup:GetParent()
    end
    local name = popup and popup.GetName and popup:GetName()
    if not name then return nil end
    return getglobal(name .. "EditBox")
end

-- 将工具 Tooltip 绑定到 UIParent（供保存/加载时探测动作与物品名称）
local function ABP_TooltipAttach()
    if ABP_Tooltip and ABP_Tooltip.SetOwner then
        ABP_Tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
end

-- ===== 宏读取与重建 =====
-- 保存时除了宏名，还记录宏体/图标/是否角色专用，供"便携字符串"和跨角色导入后重建。
-- 重建规则：先按名字找 → 再按宏体找（已有同宏体的宏直接复用，不改名、不新建）→ 最后才新建。
local ABP_MacroIconIndex = nil

-- 宏图标贴图 → 图标序号（CreateMacro 需要序号；缓存一次，建宏时才扫）
local function ABP_GetMacroIconIndex(texture)
    if not texture or texture == "" then return nil end
    if not ABP_MacroIconIndex then
        ABP_MacroIconIndex = {}
        local count = (GetNumMacroIcons and GetNumMacroIcons()) or 0
        for i = 1, count do
            local path = GetMacroIconInfo(i)
            if path then ABP_MacroIconIndex[path] = i end
        end
    end
    return ABP_MacroIconIndex[texture]
end

-- 按名字找宏序号：优先用 GetMacroIndexByName，没有该接口时退回逐个扫（1.12 也兜住）
local function ABP_FindMacroIndexByName(name)
    if not name or name == "" then return nil end
    if GetMacroIndexByName then
        local idx = GetMacroIndexByName(name)
        if idx and idx > 0 then return idx end
    end
    for i = 1, 54 do
        local mname = GetMacroInfo(i)
        if mname == name then return i end
    end
    return nil
end

-- 按宏体找宏序号：用于"按宏体去重"，避免同内容的宏被重复创建
local function ABP_FindMacroIndexByBody(body)
    if not body or body == "" then return nil end
    for i = 1, 54 do
        local _, _, mbody = GetMacroInfo(i)
        if mbody == body then return i end
    end
    return nil
end

-- 读取一个宏的完整信息（名字/图标/宏体/是否角色专用）；indexOrName 可传序号或宏名
local function ABP_ReadMacroInfo(indexOrName)
    local idx = indexOrName
    if type(indexOrName) == "string" then idx = ABP_FindMacroIndexByName(indexOrName) end
    if not idx or idx <= 0 then return nil end

    local name, icon, body, isLocal = GetMacroInfo(idx)
    if not name or not body then return nil end

    -- 部分客户端会多返回一个"是否角色专用"；读不到时用全局宏数量判断分界（全局宏排在序号前面）
    local perchar = isLocal
    if perchar == nil then
        local numGlobal = 0
        if GetNumMacros then
            local _, globalCount = GetNumMacros()
            numGlobal = globalCount or 0
        end
        perchar = (numGlobal > 0) and (idx > numGlobal) or false
    end

    return {
        icon = icon or "",
        body = body,
        perchar = (perchar and "1" or "0"),
    }
end

-- 确保某个宏存在，返回宏序号；失败时返回 nil + 原因
-- macroBodies: profile.macroBodies，键是宏名，值是 { icon, body, perchar }
local function ABP_EnsureMacro(mname, macroBodies)
    if not mname or mname == "" then return nil end

    local idx = ABP_FindMacroIndexByName(mname)
    if idx then return idx end

    local info = macroBodies and macroBodies[mname]
    if not info or not info.body or info.body == "" then
        return nil, "找不到这个宏"
    end

    -- 已有同宏体的宏：直接复用，不改名、不新建（跨账号导入时不破坏对方已有宏）
    idx = ABP_FindMacroIndexByBody(info.body)
    if idx then return idx end

    local iconIndex = ABP_GetMacroIconIndex(info.icon) or 1
    local newIdx = CreateMacro(mname, iconIndex, info.body, (info.perchar == "1"))
    if newIdx then return newIdx end
    return nil, "没有空余的宏位"
end

-- ===== 按键绑定：保存 / 恢复 =====
-- 只处理动作条按钮的绑定命令（主条、各附加条、奖励条），不碰移动/聊天等其它按键。
-- 绑定跟着按钮走，而不是跟着动作槽走：主条翻页时同一组 ACTIONBUTTON 键位仍然有效。
local ABP_BINDING_PATTERNS = {
    "^ACTIONBUTTON%d+$",
    "^MULTIACTIONBAR%d+BUTTON%d+$",
    "^BONUSACTIONBUTTON%d+$",
}

local function ABP_IsActionBarBinding(command)
    if not command or command == "" then return false end
    for k = 1, #ABP_BINDING_PATTERNS do
        if string.find(command, ABP_BINDING_PATTERNS[k]) then return true end
    end
    return false
end

-- 读取当前动作条按键绑定：返回 { [command] = { key1, key2 } }
-- 有枚举接口就枚举（自动覆盖客户端实际存在的所有动作条），没有就按已知命令逐个查。
local function ABP_CollectBindings()
    local result = {}
    if GetNumBindings and GetBinding then
        local count = GetNumBindings() or 0
        for i = 1, count do
            local command, key1, key2 = GetBinding(i)
            if ABP_IsActionBarBinding(command) and key1 then
                result[command] = { key1, key2 }
            end
        end
        return result
    end

    for n = 1, 12 do
        local commands = {
            "ACTIONBUTTON" .. n,
            "BONUSACTIONBUTTON" .. n,
        }
        for bar = 1, 6 do
            commands[#commands + 1] = "MULTIACTIONBAR" .. bar .. "BUTTON" .. n
        end
        for k = 1, #commands do
            local command = commands[k]
            if GetBindingKey then
                local key1, key2 = GetBindingKey(command)
                if key1 then result[command] = { key1, key2 } end
            end
        end
    end
    return result
end

-- 用存档里的键位完整覆盖当前动作条按键：
--   1) 先清掉当前所有动作条命令的键位（存档里没记录的旧键位不会残留）；
--   2) 再逐条设置存档里的键；
--   3) 若某个键当前被非动作条命令占用，则跳过并记录冲突，避免误伤其它按键。
-- 返回 恢复的键位数量, 冲突说明列表
local function ABP_ApplyBindings(saved)
    if not saved or not SetBinding then return 0, {} end

    -- 先清掉当前所有动作条键位，再按存档重建；这样存档里没有的旧键位不会残留
    local current = ABP_CollectBindings()
    for _, keys in pairs(current) do
        if keys[1] then SetBinding(keys[1], nil) end
        if keys[2] then SetBinding(keys[2], nil) end
    end

    local applied = 0
    local conflicts = {}
    for command, keys in pairs(saved) do
        if ABP_IsActionBarBinding(command) then
            for k = 1, 2 do
                local key = keys[k]
                if key and key ~= "" then
                    local existing = GetBindingAction and GetBindingAction(key) or nil
                    if existing and existing ~= "" and existing ~= command
                       and not ABP_IsActionBarBinding(existing) then
                        conflicts[#conflicts + 1] = key .. " 已被 " .. existing .. " 占用，未覆盖"
                    else
                        SetBinding(key, command)
                        applied = applied + 1
                    end
                end
            end
        end
    end

    if SaveBindings then
        local set = GetCurrentBindingSet and GetCurrentBindingSet() or 1
        SaveBindings(set)
    end
    return applied, conflicts
end

-- ===== 保存任务 =====
-- 一帧之内对几十个槽位做 SetAction（生成 Tooltip）+ PickupAction/PlaceAction 会造成明显卡顿，
-- 所以保存拆到多帧执行；而且只有真的发生变化的动作条才会走到这里（见上面的触发源）。
local ABP_Job = nil            -- 进行中的保存任务
local ABP_JobSlotsPerFrame = 6 -- 每帧处理的槽位数（越小越不卡，总耗时越长）
local ABP_ScanOnlySlotsPerFrame = 3 -- "只扫不写"的预热/自检任务用更小的步长，尽量不打扰游戏

-- 中断进行中的保存任务（加载配置前、或新的保存请求到来时）
local function ABP_JobAbort()
    if not ABP_Job then return end
    SetCVar("autoSelfCast", ABP_Job.scStatus)
    ABP_Job = nil
end

-- 清空某个槽位的分类缓存（动作被清掉、或读不出内容时）
local function ABP_ForgetSlot(i)
    ABP_SlotTexture[i] = nil
    ABP_SlotKind[i] = nil
    ABP_SlotName[i] = nil
    ABP_SlotRank[i] = nil
end

-- 完整扫描单个槽位：宏 -> 技能 -> 物品
-- 3.3.5+：GetActionInfo 直接给出类型，不需要动光标（也就不会踩到战斗中的 #nocombat 限制）
-- 1.12：没有 GetActionInfo，沿用"拾起 -> CursorHasSpell 判断 -> 放回"的探测法
-- 顺带记下该槽位的分类，供加载时判断"这个技能/物品其实已经在位"
local function ABP_ScanSlot(dest, i)
    if not HasAction(i) then
        ABP_ForgetSlot(i)
        return
    end

    local texture = GetActionTexture(i)
    local macroText = GetActionText(i)
    ABP_SlotTexture[i] = texture

    if macroText and macroText ~= "" then
        ABP_SlotKind[i] = "macro"
        ABP_SlotName[i] = macroText
        ABP_SlotRank[i] = nil
        dest.macros[i] = macroText
        -- 一并记录宏体/图标/是否角色专用：导出成便携字符串后，换角色/换账号也能重建宏
        local details = ABP_ReadMacroInfo(macroText)
        if details then
            if not dest.macroBodies then dest.macroBodies = {} end
            dest.macroBodies[macroText] = details
        end
        return
    end

    local isSpell = false
    if ABP_IS_MODERN then
        -- 新客户端：直接问客户端这个槽位是什么，不动光标
        isSpell = (GetActionInfo(i) == "spell")
    else
        -- 1.12：没有类型查询接口，只能靠"拾起来看光标上是技能还是物品"来判定
        PickupAction(i)
        isSpell = CursorHasSpell()
        PlaceAction(i)
    end

    -- 名字/等级一律从 Tooltip 读（两个客户端表现一致）；1.12 下要在拾取/放回之后再读才稳
    ABP_Tooltip:ClearLines()
    ABP_Tooltip:SetAction(i)

    if isSpell then
        local spellName, rankText = ABP_GetTooltipLine1()
        if spellName and spellName ~= "" then
            ABP_SlotKind[i] = "spell"
            ABP_SlotName[i] = spellName
            ABP_SlotRank[i] = rankText
            dest.spells[i] = {
                name = spellName,
                rank = rankText,
            }
        else
            ABP_SlotKind[i] = nil
            ABP_SlotName[i] = nil
            ABP_SlotRank[i] = nil
        end
    else
        local itemName = (select(1, ABP_GetTooltipLine1()))
        if itemName and itemName ~= "" then
            ABP_SlotKind[i] = "item"
            ABP_SlotName[i] = itemName
            ABP_SlotRank[i] = nil
            dest.items[i] = itemName
        else
            ABP_SlotKind[i] = nil
            ABP_SlotName[i] = nil
            ABP_SlotRank[i] = nil
        end
    end
end

-- 扫描时"有动作却什么也没解析出来"的槽位（Tooltip 读不出来时会出现）：
-- 沿用上次存档里的内容，宁可保留旧数据，也不要把槽位悄悄清掉。返回沿用了多少个。
local function ABP_CarryOverUnreadable(previous, dest)
    if not previous then return 0 end
    local carried = 0
    for i = 1, ABP_MAX_SLOTS do
        if HasAction(i)
           and not dest.spells[i] and not dest.macros[i] and not dest.items[i] then
            local sp = previous.spells and previous.spells[i]
            local mc = previous.macros and previous.macros[i]
            local it = previous.items and previous.items[i]
            if sp then
                dest.spells[i] = sp
                carried = carried + 1
            elseif mc then
                dest.macros[i] = mc
                if previous.macroBodies and previous.macroBodies[mc] then
                    if not dest.macroBodies then dest.macroBodies = {} end
                    dest.macroBodies[mc] = previous.macroBodies[mc]
                end
                carried = carried + 1
            elseif it then
                dest.items[i] = it
                carried = carried + 1
            end
        end
    end
    return carried
end

-- 汇总两份配置的槽位差异，仅用于调试输出（最多列 8 条）
local function ABP_DiffSummary(old, new)
    local parts = {}
    local function describe(v)
        if type(v) == "table" then
            local text = tostring(v.name or "?")
            if v.rank and v.rank ~= "" then text = text .. " " .. v.rank end
            return text
        end
        if v == nil then return "空" end
        return tostring(v)
    end

    for _, group in ipairs({ "spells", "macros", "items" }) do
        local ta = (old and old[group]) or {}
        local tb = (new and new[group]) or {}
        local slots = {}
        for k in pairs(ta) do slots[k] = true end
        for k in pairs(tb) do slots[k] = true end

        local keys = {}
        for k in pairs(slots) do table.insert(keys, k) end
        table.sort(keys)

        for _, k in ipairs(keys) do
            local a, b = ta[k], tb[k]
            local changed
            if type(a) == "table" or type(b) == "table" then
                changed = type(a) ~= type(b) or type(a) == "table" and (a.name ~= b.name or a.rank ~= b.rank)
            else
                changed = a ~= b
            end
            if changed then
                table.insert(parts, group .. " 槽" .. k .. " " .. describe(a) .. " → " .. describe(b))
                if table.getn(parts) >= 8 then
                    return table.concat(parts, "；") .. " …"
                end
            end
        end
    end

    if table.getn(parts) == 0 then return "无" end
    return table.concat(parts, "；")
end

-- 自检结果：把当前动作条（刚扫出来的 dest）与配置逐槽比对后报告。
-- 用来回答"加载后动作条为什么跟存档不一样"——差异会直接列出来（最多 8 条）。
local function ABP_ReportVerify(profileName, dest)
    local profile = ABP_PlayerName and ABP_Layout and ABP_Layout[ABP_PlayerName]
        and ABP_Layout[ABP_PlayerName][profileName]
    if not profile then
        ABP_Msg("|cffff5555[ABP]|r 自检失败：配置 " .. tostring(profileName) .. " 已经不在了.")
        return
    end

    local diff = ABP_DiffSummary(profile, dest)
    if diff == "无" then
        ABP_Msg("|cff33aaff[ABP]|r 加载自检（" .. profileName .. "）：当前动作条与存档完全一致.")
        return
    end

    ABP_Msg("|cffff5555[ABP]|r 加载自检（" .. profileName .. "）：与存档不一致（存档 → 现状）：")
    ABP_Msg("  " .. diff)
end

-- 保存当前动作条到指定配置（异步：真正的扫描与写入由 ABP_RunSaveJob 分帧完成）
-- silent 为 true 时不输出提示；返回是否已开始执行
function ABP_SaveProfile(profileName, silent)
    if not profileName or profileName == "" then return false end
    if not ABP_PlayerName then return false end
    if not ABP_Layout then ABP_Layout = {} end
    if not ABP_Layout[ABP_PlayerName] then ABP_Layout[ABP_PlayerName] = {} end

    if ABP_Job then ABP_JobAbort() end

    ABP_TooltipAttach()

    ABP_Job = {
        name = profileName,
        silent = silent,
        phase = "scan",  -- scan=分帧完整扫描 done=比对写入
        i = 0,           -- 已处理到的槽位
        dest = {
            spells = {},  -- [slot] = { name=, rank= }
            macros = {},  -- [slot] = macroName
            items  = {},  -- [slot] = itemName
            macroBodies = {}, -- [macroName] = { icon=, body=, perchar= }
        },
        previous = ABP_Layout[ABP_PlayerName][profileName],
        scStatus = GetCVar("autoSelfCast"),
    }

    -- autoSelfCast 只在任务期间关闭一次，避免每帧改 CVar 引起动作按钮整体刷新
    SetCVar("autoSelfCast", 0)

    ABP_Dbg('开始扫描动作条（"' .. profileName .. '"）')
    return true
end

-- 分帧执行保存任务：每帧最多处理 ABP_JobSlotsPerFrame 个槽位
function ABP_RunSaveJob()
    local job = ABP_Job
    if not job then return end

    -- 每帧处理多少个槽位：自检任务用更小的步长
    local per = job.slotsPerFrame or ABP_JobSlotsPerFrame
    local last = job.i + per
    if last > ABP_MAX_SLOTS then last = ABP_MAX_SLOTS end

    -- 第一段：分帧完整扫描（宏/技能/物品）
    if job.phase == "scan" then
        -- 1.12 的探测法要动光标，玩家正在拖拽时先让路；3.3.5 用 GetActionInfo 不碰光标，无需暂停
        if not ABP_IS_MODERN and ABP_CursorBusy() then
            ABP_Dbg("光标上有物品/技能，暂停扫描")
            return
        end

        for i = job.i + 1, last do
            ABP_ScanSlot(job.dest, i)
        end
        job.i = last

        if job.i >= ABP_MAX_SLOTS then
            SetCVar("autoSelfCast", job.scStatus) -- 扫描结束，还原 CVar
            job.phase = "done"
        end
        return
    end

    -- 收尾：写入（自检任务只比对、不写）
    ABP_Job = nil

    -- "只扫不写 + 比对"的自检任务
    if job.verifyProfile then
        ABP_ReportVerify(job.verifyProfile, job.dest)
        ABP_Dbg("自检扫描完成")
        return
    end

    -- 有动作却什么都没读出来的槽位：沿用上次的内容，避免一次读失败就把槽位清掉
    local carriedCount = ABP_CarryOverUnreadable(job.previous, job.dest)
    if carriedCount > 0 then
        ABP_Dbg("保存：有 " .. carriedCount .. " 个槽位读不出来，沿用上次的内容")
    end

    ABP_Dbg('写入 "' .. job.name .. '"：' .. ABP_DiffSummary(job.previous, job.dest))

    -- 按键绑定跟动作条一起存：绑定的是按钮，不是槽位内容
    job.dest.bindings = ABP_CollectBindings()

    ABP_Layout[ABP_PlayerName][job.name] = job.dest
    if not job.silent then
        ABP_Msg('配置文件 "' .. job.name .. '" 已保存.')
    end
end

-- "只扫不写 + 与指定配置比对"的自检任务：给加载后的自动校验和 /abprofile 对比 用
function ABP_StartVerifyJob(profileName)
    if ABP_Job or not ABP_PlayerName then return false end
    if not ABP_Layout or not ABP_Layout[ABP_PlayerName]
       or not ABP_Layout[ABP_PlayerName][profileName] then
        return false
    end

    ABP_TooltipAttach()

    ABP_Job = {
        verifyProfile = profileName,
        silent = true,
        slotsPerFrame = ABP_ScanOnlySlotsPerFrame,
        phase = "scan",
        i = 0,
        dest = { spells = {}, macros = {}, items = {}, macroBodies = {} },
        scStatus = GetCVar("autoSelfCast"),
    }

    SetCVar("autoSelfCast", 0)
    ABP_Dbg("开始自检扫描（对比 " .. profileName .. "）")
    return true
end

-- 扫描法术书，构建映射（只找需要的技能，找齐即停）。返回：
--   map.exact  = ["技能名 等级"] -> 法术书槽位
--   map.byName = [技能名]        -> 同名的第一个槽位（兜底用）
-- 为什么需要 byName 兜底：3.3.5 的 Tooltip 等级文本可能与法术书里的 subText 不完全一致（或读不到等级），
-- 只按"名字+等级"找会让本来能恢复的技能报"法术书里找不到"。只在存档没记等级时才用 byName。
local function ABP_BuildNeededSpellMap(neededSpellKeys)
    local map = { exact = {}, byName = {} }
    if not neededSpellKeys or not next(neededSpellKeys) then return map end

    local remaining = {}
    local remainingCount = 0
    for key in pairs(neededSpellKeys) do
        remaining[key] = true
        remainingCount = remainingCount + 1
    end

    for tab = 1, MAX_SKILLLINE_TABS do
        local name, _, offset, numSpells = GetSpellTabInfo(tab)
        if not name then break end
        for s = offset + 1, offset + numSpells do
            local n, r = GetSpellName(s, BOOKTYPE_SPELL)
            if n and n ~= "" then
                if map.byName[n] == nil then map.byName[n] = s end
                local key = ABP_ComposeSpellKey(n, (r ~= "" and r or nil))
                if key and remaining[key] then
                    map.exact[key] = s
                    remaining[key] = nil
                    remainingCount = remainingCount - 1
                end
            end
        end
        if remainingCount == 0 then break end -- 需要的技能全找到了，后面的页不用再扫
    end
    return map
end

-- 遍历 19 个装备位，构建"物品名 -> 装备槽位"映射（找齐即停）
local function ABP_FindItemsInEquipment(neededItems)
    local equipMap = {}
    if not neededItems or not next(neededItems) then return equipMap end

    ABP_TooltipAttach()
    local remaining = {}
    local leftCount = 0
    for name in pairs(neededItems) do remaining[name] = true; leftCount = leftCount + 1 end

    for slot = 1, 19 do
        ABP_Tooltip:ClearLines()
        local hasItem = ABP_Tooltip:SetInventoryItem("player", slot)
        if hasItem then
            local itemName = (select(1, ABP_GetTooltipLine1()))
            if itemName and remaining[itemName] then
                equipMap[itemName] = slot
                remaining[itemName] = nil
                leftCount = leftCount - 1
                if leftCount == 0 then
                    break
                end
            end
        end
    end
    return equipMap
end

-- 遍历背包与随身包，构建"物品名 -> {bag, slot}"映射（找齐即停）
local function ABP_FindItemsInBags(neededItems)
    local bagMap = {}
    if not neededItems or not next(neededItems) then return bagMap end

    ABP_TooltipAttach()
    local remaining = {}
    local leftCount = 0
    for name in pairs(neededItems) do remaining[name] = true; leftCount = leftCount + 1 end

    for bag = 0, NUM_BAG_SLOTS do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local texture = (select(1, GetContainerItemInfo(bag, slot)))
                if texture then
                    ABP_Tooltip:ClearLines()
                    ABP_Tooltip:SetBagItem(bag, slot)
                    local itemName = (select(1, ABP_GetTooltipLine1()))
                    if itemName and remaining[itemName] then
                        bagMap[itemName] = { bag = bag, slot = slot }
                        remaining[itemName] = nil
                        leftCount = leftCount - 1
                        if leftCount == 0 then
                            return bagMap
                        end
                    end
                end
            end
        end
    end
    return bagMap
end

-- 加载配置到动作条（完全覆盖当前布局）
-- 先预构建技能/物品映射表，再按槽位回填；配置中为空的槽位会被清空
-- 3.3.5 上拾取/放置类 API 受战斗限制，战斗中调用会被拒绝：这里改为"记下来，脱战后自动补做"
function ABP_LoadProfile(profileName)
    if not ABP_PlayerName or not ABP_Layout or not ABP_Layout[ABP_PlayerName]
       or not ABP_Layout[ABP_PlayerName][profileName] then
        ABP_Msg('配置文件 "' .. tostring(profileName) .. '" 以前没有保存，无法加载.')
        return
    end

    if ABP_InCombat() then
        ABP_QueueLoad(profileName)
        return
    end

    -- 有保存任务在跑就先中断，避免两个流程同时操作动作条
    ABP_JobAbort()

    local profile = ABP_Layout[ABP_PlayerName][profileName]
    local spells = profile.spells or {}
    local macros = profile.macros or {}
    local items  = profile.items  or {}
    local macroBodies = profile.macroBodies or {}

    local neededSpellKeys = {}
    local neededItemNames = {}

    for slot, info in pairs(spells) do
        local key = ABP_ComposeSpellKey(info.name, info.rank)
        if key then neededSpellKeys[key] = true end
    end
    for slot, itemName in pairs(items) do
        if itemName and itemName ~= "" then neededItemNames[itemName] = true end
    end

    local spellMap      = ABP_BuildNeededSpellMap(neededSpellKeys)
    local equipItemToId = ABP_FindItemsInEquipment(neededItemNames)

    local bagItemToLoc
    do
        -- 只在装备位上找不到的物品，才继续去背包里找
        local remaining = {}
        for name in pairs(neededItemNames) do
            if not equipItemToId[name] then remaining[name] = true end
        end
        bagItemToLoc = ABP_FindItemsInBags(remaining)
    end

    ABP_TooltipAttach()
    local scStatus = GetCVar("autoSelfCast")
    SetCVar("autoSelfCast", 0)

    local placedCount, clearedCount = 0, 0
    local missed = {} -- 存档里有、这次没能放回去的槽位（原因一起记下来）

    for i = 1, ABP_MAX_SLOTS do
        repeat
            local sp = spells[i]
            if sp then
                local key = ABP_ComposeSpellKey(sp.name, sp.rank)
                local sid = key and spellMap.exact[key] or nil
                if not sid and (not sp.rank or sp.rank == "") then
                    -- 存档里没记等级（3.3.5 上 Tooltip 读不到等级时会出现）：只按技能名兜底
                    sid = spellMap.byName[sp.name]
                end
                if sid then
                    PickupSpell(sid, BOOKTYPE_SPELL)
                    PlaceAction(i)
                    ClearCursor() -- 清空光标，防止被覆盖槽位的旧内容残留并干扰后续槽位
                    placedCount = placedCount + 1
                elseif ABP_SlotKind[i] == "spell" and ABP_SlotName[i] == sp.name
                       and GetActionTexture(i) == ABP_SlotTexture[i] then
                    -- 法术书里找不到，但这个槽位现在挂着的就是它（比如物品给的技能）：算它已经到位
                    placedCount = placedCount + 1
                else
                    table.insert(missed, "技能 槽" .. i .. " " .. tostring(sp.name)
                        .. (sp.rank and (" " .. sp.rank) or "") .. "（法术书里找不到）")
                end
                break
            end

            local mname = macros[i]
            if mname and mname ~= "" then
                local picked = false
                local why = nil
                if GetSuperMacroInfo and GetSuperMacroInfo(mname, "texture") then
                    PickupMacro(0, mname)
                    PlaceAction(i)
                    ClearCursor() -- 清空光标残留
                    picked = true
                else
                    -- 先按名字找；找不到就按存档里的宏体重建（同宏体的已有宏直接复用，不会重复创建）
                    local idx
                    idx, why = ABP_EnsureMacro(mname, macroBodies)
                    if idx and idx > 0 then
                        PickupMacro(idx)
                        PlaceAction(i)
                        ClearCursor() -- 清空光标残留
                        picked = true
                    end
                end
                if picked then
                    placedCount = placedCount + 1
                elseif ABP_SlotKind[i] == "macro" and ABP_SlotName[i] == mname
                       and GetActionTexture(i) == ABP_SlotTexture[i] then
                    -- 找不到这个宏，但槽位上挂的就是它：算它已经到位
                    placedCount = placedCount + 1
                else
                    table.insert(missed, "宏 槽" .. i .. " " .. mname
                        .. "（" .. (why or "找不到这个宏") .. "）")
                end
                break
            end

            local iname = items[i]
            if iname and iname ~= "" then
                local eslot = equipItemToId[iname]
                if eslot then
                    PickupInventoryItem(eslot)
                    PlaceAction(i)
                    ClearCursor() -- 清空光标残留
                    placedCount = placedCount + 1
                    break
                end
                local loc = bagItemToLoc[iname]
                if loc then
                    PickupContainerItem(loc.bag, loc.slot)
                    PlaceAction(i)
                    ClearCursor() -- 清空光标残留
                    placedCount = placedCount + 1
                    break
                end
                -- 背包和装备上都没有：如果这个槽位现在挂着的就是同一个物品，那它其实已经在位了
                if ABP_SlotKind[i] == "item" and ABP_SlotName[i] == iname
                   and GetActionTexture(i) == ABP_SlotTexture[i] then
                    placedCount = placedCount + 1
                    break
                end
                table.insert(missed, "物品 槽" .. i .. " " .. iname .. "（背包和装备上都没有）")
                break
            end

            -- 保存的配置中该槽位为空：拾起当前动作并丢弃，实现完全覆盖
            if HasAction(i) then clearedCount = clearedCount + 1 end
            PickupAction(i)
            ClearCursor()
        until true
    end
    SetCVar("autoSelfCast", scStatus)

    -- 按键绑定：完整覆盖存档里的动作条键位；老存档没有 bindings 字段时不动当前键位
    local bindingCount, bindingConflicts = nil, nil
    if profile.bindings then
        bindingCount, bindingConflicts = ABP_ApplyBindings(profile.bindings)
    end

    ABP_Msg('配置文件 "' .. profileName .. '" 已加载：放回 ' .. placedCount .. " 个槽位，清空 "
        .. clearedCount .. " 个。")
    if bindingCount then
        ABP_Msg("  按键绑定：恢复 " .. bindingCount .. " 个键位.")
    end
    if bindingConflicts and #bindingConflicts > 0 then
        ABP_Msg("|cffff5555[ABP]|r 有 " .. #bindingConflicts .. " 个键位被其它功能占用，未覆盖：")
        for k = 1, #bindingConflicts do
            if k > 3 then
                ABP_Msg("  …还有 " .. (#bindingConflicts - 3) .. " 个")
                break
            end
            ABP_Msg("  " .. bindingConflicts[k])
        end
    end
    if table.getn(missed) > 0 then
        ABP_Msg("|cffff5555[ABP]|r 有 " .. table.getn(missed)
            .. " 个槽位没能恢复（会保持原样，所以看起来跟存档不一致）：")
        for k = 1, table.getn(missed) do
            if k > 8 then
                ABP_Msg("  …还有 " .. (table.getn(missed) - 8) .. " 个")
                break
            end
            ABP_Msg("  " .. missed[k])
        end
    end

    -- 3 秒后自检一次：把当前动作条跟这份存档逐槽比一遍，直接回答"完全覆盖到底有没有生效"
    ABP_VerifyAt = GetTime() + 3
    ABP_VerifyProfile = profileName
end

-- ===== 便携字符串：导出 / 导入 =====
-- 安全设计：只做纯数据序列化/反序列化，绝不 loadstring 执行字符串内容。
-- 格式：前缀 "ABP1:" + Base64( 一串 netstring 字段 )
--   netstring 字段 = "#长度:内容"；长度由数据自己给出，所以宏体里的换行、引号、分隔符都不用转义。
local ABP_PORTABLE_TAG = "ABP1:"
local ABP_PORTABLE_VERSION = "2" -- 2：在技能/宏/物品之后追加动作条按键段；仍兼容读取 1

local ABP_B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ABP_B64_INDEX = {}
for i = 1, 64 do
    ABP_B64_INDEX[string.sub(ABP_B64_CHARS, i, i)] = i - 1
end

local function ABP_Base64Encode(data)
    local out = {}
    local size = string.len(data)
    local i = 1
    while i <= size do
        local b1 = string.byte(data, i)
        local b2 = string.byte(data, i + 1)
        local b3 = string.byte(data, i + 2)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = string.sub(ABP_B64_CHARS, c1 + 1, c1 + 1)
        out[#out + 1] = string.sub(ABP_B64_CHARS, c2 + 1, c2 + 1)
        out[#out + 1] = b2 and string.sub(ABP_B64_CHARS, c3 + 1, c3 + 1) or "="
        out[#out + 1] = b3 and string.sub(ABP_B64_CHARS, c4 + 1, c4 + 1) or "="
        i = i + 3
    end
    return table.concat(out)
end

local function ABP_Base64Decode(data)
    if not data or data == "" then return nil end
    data = string.gsub(data, "[^%w%+/=]", "")
    local out = {}
    local buffer, bits = 0, 0
    for i = 1, string.len(data) do
        local ch = string.sub(data, i, i)
        if ch ~= "=" then
            local v = ABP_B64_INDEX[ch]
            if not v then return nil end
            buffer = buffer * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local divisor = 2 ^ bits
                out[#out + 1] = string.char(math.floor(buffer / divisor) % 256)
                buffer = buffer % divisor
            end
        end
    end
    return table.concat(out)
end

-- 打包成 netstring 序列
local function ABP_PackFields(fields)
    local out = {}
    for i = 1, #fields do
        local v = tostring(fields[i] == nil and "" or fields[i])
        out[#out + 1] = "#" .. string.len(v) .. ":" .. v
    end
    return table.concat(out)
end

-- 反解 netstring 序列：成功返回字段数组，格式不对返回 nil
local function ABP_ReadFields(data)
    local fields = {}
    local pos = 1
    local size = string.len(data)
    while pos <= size do
        if string.sub(data, pos, pos) ~= "#" then return nil end
        local colon = string.find(data, ":", pos + 1, true)
        if not colon then return nil end
        local n = tonumber(string.sub(data, pos + 1, colon - 1))
        if not n or n < 0 or colon + n > size then return nil end
        fields[#fields + 1] = string.sub(data, colon + 1, colon + n)
        pos = colon + n + 1
    end
    return fields
end

-- 取出表里所有数字键并排序，保证导出顺序稳定（便于比对/复现）
local function ABP_SortedSlotList(t)
    local list = {}
    if t then
        for k in pairs(t) do
            if type(k) == "number" then list[#list + 1] = k end
        end
    end
    table.sort(list)
    return list
end

local function ABP_CountEntries(t)
    local n = 0
    if t then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

-- 把一份配置打包成字符串（不含前缀/Base64 之外的任何加工）
local function ABP_BuildPortablePayload(name, profile)
    local fields = {}
    local function add(v) fields[#fields + 1] = v end

    add(ABP_PORTABLE_VERSION)
    add(name)

    local spellSlots = ABP_SortedSlotList(profile.spells)
    add(#spellSlots)
    for _, slot in ipairs(spellSlots) do
        local s = profile.spells[slot]
        add(slot); add(s.name or ""); add(s.rank or "")
    end

    local macroSlots = ABP_SortedSlotList(profile.macros)
    local bodies = profile.macroBodies or {}
    add(#macroSlots)
    for _, slot in ipairs(macroSlots) do
        local mname = profile.macros[slot] or ""
        -- 优先用存档里的宏信息；老存档没有时现场向客户端读一次（本机存在同名宏才读得到）
        local info = bodies[mname] or ABP_ReadMacroInfo(mname) or {}
        add(slot); add(mname); add(info.body or ""); add(info.icon or ""); add(info.perchar or "0")
    end

    local itemSlots = ABP_SortedSlotList(profile.items)
    add(#itemSlots)
    for _, slot in ipairs(itemSlots) do
        add(slot); add(profile.items[slot] or "")
    end

    -- 按键段：命令名 + 主键 + 副键；只导出动作条按钮的绑定
    local bindings = profile.bindings or {}
    local commands = {}
    for command in pairs(bindings) do
        if ABP_IsActionBarBinding(command) then commands[#commands + 1] = command end
    end
    table.sort(commands)
    add(#commands)
    for _, command in ipairs(commands) do
        local keys = bindings[command]
        add(command); add(keys[1] or ""); add(keys[2] or "")
    end

    return ABP_PackFields(fields)
end

-- 解析便携字符串；成功返回 profile 表，失败返回 nil + 原因
local function ABP_ParsePortable(text)
    local raw = string.gsub(text or "", "%s+", "")
    if string.sub(raw, 1, string.len(ABP_PORTABLE_TAG)) ~= ABP_PORTABLE_TAG then
        return nil, "不是本插件的便携字符串（应以 ABP1: 开头）"
    end

    local payload = ABP_Base64Decode(string.sub(raw, string.len(ABP_PORTABLE_TAG) + 1))
    if not payload then return nil, "Base64 解码失败，字符串可能被截断" end

    local fields = ABP_ReadFields(payload)
    if not fields then return nil, "字符串内容已损坏" end

    local pos = 0
    local function take()
        pos = pos + 1
        return fields[pos]
    end
    local function takeText() return take() or "" end
    local function takeNum()
        local v = take()
        if v == nil then return nil end
        return tonumber(v)
    end

    local version = take()
    if version ~= "1" and version ~= "2" then return nil, "不支持的便携字符串版本" end

    local name = take()
    if not name or name == "" then return nil, "配置名为空" end

    local profile = { name = name, spells = {}, macros = {}, items = {}, macroBodies = {} }
    local skipped = 0
    local function slotOK(slot)
        if slot and slot >= 1 and slot <= ABP_MAX_SLOTS then return true end
        skipped = skipped + 1
        return false
    end

    local n = takeNum()
    if not n or n < 0 or n > ABP_MAX_SLOTS then return nil, "技能段数量异常" end
    for _ = 1, n do
        local slot = takeNum()
        local spellName = takeText()
        local rank = takeText()
        if not slot or spellName == "" then return nil, "技能段数据不完整" end
        if slotOK(slot) then
            profile.spells[slot] = { name = spellName, rank = (rank ~= "" and rank or nil) }
        end
    end

    n = takeNum()
    if not n or n < 0 or n > ABP_MAX_SLOTS then return nil, "宏段数量异常" end
    for _ = 1, n do
        local slot = takeNum()
        local mname = takeText()
        local body = takeText()
        local icon = takeText()
        local perchar = takeText()
        if not slot or mname == "" then return nil, "宏段数据不完整" end
        if slotOK(slot) then
            profile.macros[slot] = mname
            if body ~= "" and not profile.macroBodies[mname] then
                profile.macroBodies[mname] = {
                    body = body,
                    icon = icon,
                    perchar = (perchar == "1" and "1" or "0"),
                }
            end
        end
    end

    n = takeNum()
    if not n or n < 0 or n > ABP_MAX_SLOTS then return nil, "物品段数量异常" end
    for _ = 1, n do
        local slot = takeNum()
        local itemName = takeText()
        if not slot or itemName == "" then return nil, "物品段数据不完整" end
        if slotOK(slot) then
            profile.items[slot] = itemName
        end
    end

    -- 版本 2 才带按键段；版本 1 没有这段，导入后不会改动当前按键绑定
    if version == "2" then
        n = takeNum()
        if not n or n < 0 or n > 1000 then return nil, "按键段数量异常" end
        profile.bindings = {}
        for _ = 1, n do
            local command = takeText()
            local key1 = takeText()
            local key2 = takeText()
            if command == "" then return nil, "按键段数据不完整" end
            -- 只接受动作条按钮命令，避免导入字符串把任意命令绑到键上
            if ABP_IsActionBarBinding(command) then
                profile.bindings[command] = {
                    (key1 ~= "" and key1 or nil),
                    (key2 ~= "" and key2 or nil),
                }
            end
        end
    end

    return profile, nil, skipped
end

-- 把一份配置编码成可复制/粘贴的便携字符串
function ABP_BuildPortableString(profileName)
    local profile = ABP_PlayerName and ABP_Layout and ABP_Layout[ABP_PlayerName]
        and ABP_Layout[ABP_PlayerName][profileName]
    if not profile then
        return nil, '配置 "' .. tostring(profileName) .. '" 还没有保存过'
    end
    return ABP_PORTABLE_TAG .. ABP_Base64Encode(ABP_BuildPortablePayload(profileName, profile))
end

-- 待确认覆盖的导入结果（弹窗确认后才真正写入）
local ABP_PendingImport = nil

local function ABP_StoreImportedProfile(profile)
    if not ABP_PlayerName then return false end
    if not ABP_Layout then ABP_Layout = {} end
    if not ABP_Layout[ABP_PlayerName] then ABP_Layout[ABP_PlayerName] = {} end
    ABP_Layout[ABP_PlayerName][profile.name] = {
        spells = profile.spells or {},
        macros = profile.macros or {},
        items = profile.items or {},
        macroBodies = profile.macroBodies or {},
        bindings = profile.bindings,
    }
    return true
end

-- 从字符串导入一份配置：只写入 SavedVariables，不会立刻动动作条
function ABP_ImportFromString(text)
    if not ABP_PlayerName then
        ABP_Msg("|cffff5555[ABP]|r 角色信息还没加载完成，稍后再试.")
        return false
    end

    local profile, err, skipped = ABP_ParsePortable(text)
    if not profile then
        ABP_Msg("|cffff5555[ABP]|r 导入失败：" .. (err or "字符串内容无法识别"))
        return false
    end

    local existing = ABP_Layout and ABP_Layout[ABP_PlayerName]
        and ABP_Layout[ABP_PlayerName][profile.name]
    if existing then
        ABP_PendingImport = profile
        StaticPopup_Show("ABP_ImportOverwrite", profile.name)
        return true
    end

    ABP_StoreImportedProfile(profile)
    local importedMsg = '|cff33aaff[ABP]|r 已导入配置 "' .. profile.name .. '"：技能 '
        .. ABP_CountEntries(profile.spells) .. " 个，宏 " .. ABP_CountEntries(profile.macros)
        .. " 个，物品 " .. ABP_CountEntries(profile.items) .. " 个"
    if profile.bindings then
        importedMsg = importedMsg .. "，按键 " .. ABP_CountEntries(profile.bindings) .. " 个"
    end
    ABP_Msg(importedMsg .. ".")
    if skipped and skipped > 0 then
        ABP_Msg("  有 " .. skipped .. " 条槽位超出本客户端范围，已忽略.")
    end
    ABP_Msg('  用 /abprofile 加载 "' .. profile.name .. '" 或从菜单里点它即可应用.')
    return true
end

-- 打开窗口并填入导出结果（全选，方便直接复制）
function ABP_Portable_ShowExport(profileName)
    local text, err = ABP_BuildPortableString(profileName)
    if not text then
        ABP_Msg("|cffff5555[ABP]|r " .. err)
        return
    end

    local frame = getglobal("ABP_PortableFrame")
    local box = getglobal("ABP_PortableFrameEditBox")
    if not frame or not box then return end

    frame:Show()
    box:SetText(text)
    box:HighlightText()
    box:SetFocus()
    ABP_Msg('配置 "' .. profileName .. '" 的便携字符串已生成并全选，复制后可在其他角色/账号导入.')
end

-- 打开窗口等待粘贴字符串
function ABP_Portable_ShowImport()
    local frame = getglobal("ABP_PortableFrame")
    local box = getglobal("ABP_PortableFrameEditBox")
    if not frame or not box then return end

    frame:Show()
    box:SetText("")
    box:SetFocus()
    ABP_Msg("把便携字符串粘贴到窗口里，然后点“导入”.")
end

-- 窗口“导入”按钮：读取输入框内容并导入
function ABP_Portable_Import()
    local box = getglobal("ABP_PortableFrameEditBox")
    if not box then return end
    if ABP_ImportFromString(box:GetText() or "") then
        local frame = getglobal("ABP_PortableFrame")
        if frame then frame:Hide() end
    end
end

-- 列出当前角色的所有配置名
function ABP_ListProfiles()
    if not ABP_PlayerName or not ABP_Layout or not ABP_Layout[ABP_PlayerName]
       or hasElements(ABP_Layout[ABP_PlayerName]) == 0 then
        ABP_Msg("你没有为这个人物保存的配置文件.")
        return
    end
    ABP_Msg("这个人物的配置文件有:")
    for profileName in pairs(ABP_Layout[ABP_PlayerName]) do
        ABP_Msg("    " .. profileName)
    end
end

-- 删除指定配置
function ABP_RemoveProfile(profileName)
    if not ABP_PlayerName or not ABP_Layout
       or not ABP_Layout[ABP_PlayerName]
       or not ABP_Layout[ABP_PlayerName][profileName] then
        ABP_Msg("你没有配置文件 '" .. tostring(profileName) .. "' 保存在这个人物上.")
        return
    end
    ABP_Layout[ABP_PlayerName][profileName] = nil
    ABP_Msg("配置文件 '" .. profileName .. "' 已经删除.")
end



-- 由独立计时帧每帧驱动：推进进行中的任务（保存任务 / 加载后的自检）
function ABP_OnUpdate(frame, elapsed)
    -- 分帧任务未完成前不启动新的
    if ABP_Job then
        ABP_RunSaveJob()
        return
    end

    -- 加载后的自检：等动作条稳定几秒再扫，避免把还没落地的改动算成差异
    if ABP_VerifyAt and GetTime() >= ABP_VerifyAt then
        local verifyName = ABP_VerifyProfile
        ABP_VerifyAt, ABP_VerifyProfile = nil, nil
        if verifyName then ABP_StartVerifyJob(verifyName) end
    end
end

-- 创建独立的计时帧（推进分帧任务）
function ABP_CreateTimerFrame()
    if ABP_TimerFrame then return end
    ABP_TimerFrame = CreateFrame("Frame", "ABP_TimerFrame", UIParent)
    ABP_TimerFrame:SetScript("OnUpdate", ABP_OnUpdate)
    ABP_TimerFrame:Show()
end

-- 插件加载：注册事件与斜杠命令
function ABP_OnLoad()
    this:RegisterEvent("VARIABLES_LOADED")
    if ABP_IS_MODERN then
        -- 只有支持该事件的新客户端才注册：用来补做战斗中推迟的加载（1.12 没有战斗锁定，不需要）
        this:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    SLASH_ABP1 = "/abprofile"
    SlashCmdList["ABP"] = function(msg) ABP_SlashCommand(msg or "") end
end

-- 事件分发：VARIABLES_LOADED 时初始化；3.3.5 上再用 PLAYER_REGEN_ENABLED 补做被战斗推迟的加载
-- （事件名显式传入：XML 里写 ABP_OnEvent(event)，1.12 与 3.3.5 都支持这么取全局 event）
function ABP_OnEvent(ev)
    ev = ev or event

    if ev == "PLAYER_REGEN_ENABLED" then
        local pending = ABP_PendingLoad
        if pending then
            ABP_PendingLoad = nil
            ABP_Msg("|cff33aaff[ABP]|r 战斗结束，加载推迟的配置 \"" .. pending .. "\".")
            ABP_LoadProfile(pending)
        end
        return
    end

    if ev ~= "VARIABLES_LOADED" then return end

    ABP_PlayerName = UnitName("player") .. " of " .. GetCVar("realmName")

    if not ABP_Layout then ABP_Layout = {} end
    if not ABP_Layout[ABP_PlayerName] then ABP_Layout[ABP_PlayerName] = {} end

    if ABP_ButtonPosition == nil then ABP_ButtonPosition = 60 end

    UIDropDownMenu_Initialize(getglobal("ABP_DropDownMenu"), ABP_DropDownMenu_OnLoad, "MENU")
    ABPButton_UpdatePosition()
    ABP_CreateTimerFrame()
end

-- 命令提示：列出所有可用命令
function ABP_PrintHelp()
    ABP_Msg("ActionBarProfiles - 动作条配置保存/加载（纯手动：不自动保存、不监听动作条）")
    ABP_Msg("  /abprofile 保存 <名字>    把当前动作条和按键绑定存成配置")
    ABP_Msg("  /abprofile 加载 <名字>    加载配置，完全覆盖当前动作条和按键绑定")
    ABP_Msg("  /abprofile 删除 <名字>    删除配置")
    ABP_Msg("  /abprofile 列表           列出本角色的所有配置")
    ABP_Msg("  /abprofile 对比 <名字>    把当前动作条跟该配置逐槽比一遍，列出差异")
    ABP_Msg("  /abprofile 导出 <名字>    生成可复制/粘贴的便携字符串（含宏体与按键，可跨角色/账号）")
    ABP_Msg("  /abprofile 导入           打开窗口，粘贴便携字符串导入成配置")
    ABP_Msg("  /abprofile debug          诊断输出开关（当前：" .. ABP_DebugLevel .. " 级）")
    ABP_Msg("不带参数的 /abprofile 就是这份提示.")
    ABP_Msg("ActionBarProfiles, 由Kronos的<Vanguard>制作, 60addons汉化")
end

-- 斜杠命令分发：解析"保存/加载/删除/列表 + 配置名"并调用对应函数
function ABP_SlashCommand(msg)
    msg = msg or ""

    -- 去掉首尾空格：/abprofile 后面多打了空格也当成没带参数
    local cmd = string.gsub(msg, "^%s*(.-)%s*$", "%1")
    if cmd == "" then
        ABP_PrintHelp()
        return
    end

    local lowerCmd = string.lower(cmd)

    -- 帮助别名
    if lowerCmd == "?" or lowerCmd == "help" or cmd == "帮助" then
        ABP_PrintHelp()
        return
    end

    -- 诊断开关：/abprofile debug
    -- 要求出现在命令开头，避免配置文件名字里含 debug 时误判
    if string.find(lowerCmd, "^%s*" .. CMD_DEBUG) then
        ABP_DebugLevel = (ABP_DebugLevel == 0) and 1 or 0
        if ABP_DebugLevel == 0 then
            ABP_Msg("ActionBarProfiles 诊断输出已关闭.")
        else
            ABP_Msg("ActionBarProfiles 诊断输出已打开：会打印扫描/写入/比对的槽位差异.")
        end
        return
    end

    -- 便携字符串导出：/abprofile 导出 <名字>
    local exportName = string.match(cmd, "^" .. CMD_EXPORT .. "%s*(.*)$")
    if exportName then
        if exportName == "" then
            ABP_Msg("用法: /abprofile 导出 <配置名>")
            ABP_ListProfiles()
        else
            ABP_Portable_ShowExport(exportName)
        end
        return
    end

    -- 便携字符串导入：/abprofile 导入（打开粘贴窗口）
    if string.sub(cmd, 1, string.len(CMD_IMPORT)) == CMD_IMPORT then
        ABP_Portable_ShowImport()
        return
    end

    for profileName in string.gfind(cmd, CMD_SAVE .. " (.*)") do
        ABP_SaveProfile(profileName)
        return
    end
    for profileName in string.gfind(cmd, CMD_LOAD .. " (.*)") do
        ABP_LoadProfile(profileName)
        return
    end
    for profileName in string.gfind(cmd, CMD_REMOVE .. " (.*)") do
        ABP_RemoveProfile(profileName)
        return
    end
    for profileName in string.gfind(cmd, CMD_CHECK .. " (.*)") do
        if not ABP_Layout or not ABP_Layout[ABP_PlayerName]
           or not ABP_Layout[ABP_PlayerName][profileName] then
            ABP_Msg('配置 "' .. profileName .. '" 还没有保存过，无法对比.')
        else
            ABP_Msg('正在把当前动作条与 "' .. profileName .. '" 逐槽比对（几秒后给结果）…')
            ABP_StartVerifyJob(profileName)
        end
        return
    end
    if string.find(cmd, CMD_LIST, 1, true) then
        ABP_ListProfiles()
        return
    end

    -- 看不懂的命令：给提示，而不是静默什么都不做
    ABP_Msg('无法识别的命令 "' .. cmd .. '"')
    ABP_PrintHelp()
end

-- 构建小地图按钮的下拉菜单
-- 含三级：主菜单（加载/保存/删除）、保存子菜单、删除子菜单
-- 菜单项回调把配置名"提前捕获"进闭包，不再靠 this 取按钮文本（1.12 传 this、3.3.5 习惯 self，闭包两版都不会踩空）
-- owner 统一取下拉菜单的父级：1.12 与 3.3.5 的初始化回调都会把下拉菜单传进来，取不到才回落到 this
function ABP_DropDownMenu_OnLoad(menu)
    menu = menu or this
    local owner = menu and menu:GetParent() or nil

    if UIDROPDOWNMENU_MENU_VALUE == "Delete menu" then
        UIDropDownMenu_AddButton({
            text = "选择要删除的布局",
            isTitle = true,
            owner = owner,
            justifyH = "CENTER",
        }, UIDROPDOWNMENU_MENU_LEVEL)

        local list = ABP_Layout and ABP_Layout[ABP_PlayerName] or nil
        if list then
            for profileName in pairs(list) do
                local pname = profileName
                UIDropDownMenu_AddButton({
                    text = pname,
                    value = pname,
                    func = function() ABP_RemoveProfile(pname) end,
                    notCheckable = 1,
                    owner = owner,
                }, UIDROPDOWNMENU_MENU_LEVEL)
            end
        end
        return
    end

    -- 保存子菜单
    if UIDROPDOWNMENU_MENU_VALUE == "Save menu" then
        UIDropDownMenu_AddButton({
            text = "选择要覆盖的布局",
            isTitle = true,
            owner = owner,
            justifyH = "CENTER",
        }, UIDROPDOWNMENU_MENU_LEVEL)

        local list = ABP_Layout and ABP_Layout[ABP_PlayerName] or nil
        if list then
            for profileName in pairs(list) do
                local pname = profileName
                UIDropDownMenu_AddButton({
                    text = pname,
                    value = pname,
                    func = function() ABP_SaveProfile(pname) end,
                    notCheckable = 1,
                    owner = owner,
                }, UIDROPDOWNMENU_MENU_LEVEL)
            end
        end

        UIDropDownMenu_AddButton({
            text = "新建...",
            func = function() StaticPopup_Show("ABP_NewProfile") end,
            notCheckable = 1,
            owner = owner,
        }, UIDROPDOWNMENU_MENU_LEVEL)
        return
    end

    -- 导出子菜单：选一个配置生成便携字符串
    if UIDROPDOWNMENU_MENU_VALUE == "Export menu" then
        UIDropDownMenu_AddButton({
            text = "选择要导出的布局",
            isTitle = true,
            owner = owner,
            justifyH = "CENTER",
        }, UIDROPDOWNMENU_MENU_LEVEL)

        local list = ABP_Layout and ABP_Layout[ABP_PlayerName] or nil
        if list then
            for profileName in pairs(list) do
                local pname = profileName
                UIDropDownMenu_AddButton({
                    text = pname,
                    value = pname,
                    func = function() ABP_Portable_ShowExport(pname) end,
                    notCheckable = 1,
                    owner = owner,
                }, UIDROPDOWNMENU_MENU_LEVEL)
            end
        end
        return
    end

    -- 主菜单
    UIDropDownMenu_AddButton({
        text = UnitName("player") .. "的动作条",
        isTitle = true,
        owner = owner,
        justifyH = "CENTER",
    }, UIDROPDOWNMENU_MENU_LEVEL)

    local list = ABP_Layout and ABP_Layout[ABP_PlayerName] or nil
    if list then
        for profileName in pairs(list) do
            local pname = profileName
            UIDropDownMenu_AddButton({
                text = pname,
                func = function() ABP_LoadProfile(pname) end,
                notCheckable = 1,
                owner = owner,
            }, UIDROPDOWNMENU_MENU_LEVEL)
        end
    end

    UIDropDownMenu_AddButton({
        text = "选项",
        isTitle = true,
        justifyH = "CENTER",
    }, UIDROPDOWNMENU_MENU_LEVEL)

    -- "保存当前动作条的布局"带子菜单
    UIDropDownMenu_AddButton({
        text = "保存当前动作条的布局",
        value = "Save menu",
        notCheckable = 1,
        hasArrow = true,
        owner = owner,
    }, UIDROPDOWNMENU_MENU_LEVEL)

    -- "导出配置为字符串"带子菜单
    UIDropDownMenu_AddButton({
        text = "导出配置为字符串",
        value = "Export menu",
        notCheckable = 1,
        hasArrow = true,
        owner = owner,
    }, UIDROPDOWNMENU_MENU_LEVEL)

    UIDropDownMenu_AddButton({
        text = "从字符串导入...",
        func = function() ABP_Portable_ShowImport() end,
        notCheckable = 1,
        owner = owner,
    }, UIDROPDOWNMENU_MENU_LEVEL)

    UIDropDownMenu_AddButton({
        text = "删除一个布局",
        value = "Delete menu",
        notCheckable = 1,
        hasArrow = true,
        owner = owner,
    }, UIDROPDOWNMENU_MENU_LEVEL)
end

-- 小地图按钮绕小地图旋转的半径
local ABP_ButtonRadius = 78

-- 按保存的角度定位小地图按钮
function ABPButton_UpdatePosition()
    ActionBarProfiles_IconFrame:SetPoint(
        "TOPLEFT", "Minimap", "TOPLEFT",
        54 - (ABP_ButtonRadius * cos(ABP_ButtonPosition)),
        (ABP_ButtonRadius * sin(ABP_ButtonPosition)) - 55
    )
end

-- 按钮被拖动时：根据鼠标相对小地图的位置实时计算角度
function ABPButton_BeingDragged()
    local xpos, ypos = GetCursorPosition()
    local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
    xpos = xmin - xpos / UIParent:GetScale() + 70
    ypos = ypos / UIParent:GetScale() - ymin - 70
    ABPButton_SetPosition(math.deg(math.atan2(ypos, xpos)))
end

-- 设置按钮角度（0~360）并持久化，随后更新按钮位置
function ABPButton_SetPosition(v)
    if v < 0 then v = v + 360 end
    ABP_ButtonPosition = v
    ABPButton_UpdatePosition()
end

-- 新建配置名的输入对话框（菜单"新建..."触发）
-- 取输入框统一走 ABP_GetPopupEditBox：1.12 回调传"确定按钮"，3.3.5 传"弹窗本身"，两种都兜住
StaticPopupDialogs["ABP_NewProfile"] = {
    text = "为当前动作条保存输入一个名称",
    button1 = SAVE,
    button2 = CANCEL,
    OnAccept = function(self)
        local box = ABP_GetPopupEditBox(self)
        if not box then return end
        local profileName = box:GetText()
        ABP_SaveProfile(profileName)
        box:SetText("")
    end,
    EditBoxOnEnterPressed = function(self)
        local box = self or this
        if not box then return end
        local profileName = box:GetText()
        ABP_SaveProfile(profileName)
        box:SetText("")
        local popup = box:GetParent()
        if popup then popup:Hide() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    hasEditBox = true,
    preferredIndex = 3,
}

-- 导入时配置名已存在的覆盖确认
StaticPopupDialogs["ABP_ImportOverwrite"] = {
    text = '配置 "%1" 已存在，要用导入的内容覆盖吗？',
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local profile = ABP_PendingImport
        ABP_PendingImport = nil
        if profile and ABP_StoreImportedProfile(profile) then
            ABP_Msg('|cff33aaff[ABP]|r 已覆盖导入配置 "' .. profile.name .. '".')
            ABP_Msg('  用 /abprofile 加载 "' .. profile.name .. '" 或从菜单里点它即可应用.')
        end
    end,
    OnCancel = function()
        ABP_PendingImport = nil
        ABP_Msg("已取消导入.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
