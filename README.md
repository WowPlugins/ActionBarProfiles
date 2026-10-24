# ActionBarProfiles（动作条保存）

> World of Warcraft **3.3.5（WotLK）** / **1.12（Turtle WoW 乌龟服 1.18）** 动作条保存/加载插件——同一份代码，自动识别客户端
> 纯手动版：**只有你主动点"保存"才会记录动作条**，插件不监听动作条改动、不自动保存、不挂钩任何游戏函数。

## 功能特性

- **一键保存 / 加载 / 删除 / 列表**：把当前动作条上的**技能、宏、物品**整体存成命名配置（Profile），随时一键恢复。
- **完全覆盖加载**：加载后动作条与保存时**完全一致**——保存时为空的动作槽位，加载后也会被清空，不会残留当前布局。
- **加载结果报告**：放回 / 清空了多少槽位；存档里有、这次没能放回去的槽位会逐条列出并给原因（技能不在法术书里、宏不存在、物品不在背包或装备上）。如果该槽位现在挂着的本来就是这个技能 / 宏 / 物品，算"已经在位"，不会误报。
- **加载后 3 秒自检**：等动作条稳定后自动扫一遍，与刚加载的存档逐槽比对，直接报"与存档完全一致"或列出差异（最多 8 条）。也可以随时用 `/abprofile 对比 <名字>` 手动比对。
- **多角色隔离**：配置按"角色名 of 服务器名"隔离，互不干扰；同一角色可保存多套配置。
- **便携字符串（可跨角色/账号）**：`/abprofile 导出 <名字>` 生成一段 `ABP1:` 开头的字符串，在别的角色/账号用 `/abprofile 导入` 粘贴即可得到同一份配置。字符串是 Base64 + 长度前缀的**纯数据**（不 `loadstring`、不执行任何代码），损坏或截断会被拒绝。
- **宏重建**：导出时把宏体、图标、是否角色宏一起带走；加载/导入时先按**宏名**找，找不到再按**宏体**去重（已有同宏体的宏直接复用，不改名、不删除），最后才在有空位时新建。
- **按键绑定一起保存 / 导出**：保存配置时同时记录动作条按钮的按键（主键 + 副键），加载时完整覆盖动作条键位；便携字符串里也带这一段。只处理 `ACTIONBUTTON`、`MULTIACTIONBAR*BUTTON`、`BONUSACTIONBUTTON`，移动、聊天等其它按键不受影响。
- **双版本**：同一份代码跑 3.3.5 与 1.12——自动探测客户端；3.3.5 只遍历 1~120 玩家动作槽（121 以上是宠物/载具条，已排除），1.12 仍是 1~144。
- **战斗中自动延后**：3.3.5 的战斗锁定会拒绝改动作条数组，此时点"加载"不会失败——插件先记下配置，脱战后自动补做。
- **小地图按钮**：左键弹出菜单操作；右键拖动按钮绕小地图圆周定位，位置自动记忆。
- **中文斜杠命令**：`/abprofile` 系列命令。

**没有自动保存。** 插件的改动（保存/加载/删除）全部由你手动触发；动作条上拖来拖去不会被记录，也不会写进存档。如果哪天想要"改动后自动保存 / 退出时自动补存"，旧版本备份在 `ActionBarProfiles.lua.bak-autosave`（见文末）。

## 安装方法

1. 将 `ActionBarProfiles` 文件夹放入 `Interface\AddOns\` 目录。
2. 确认 `.toc` 里的 `## Interface` 与你的客户端一致：当前是 `30300`（3.3.5）；如果拿到乌龟服（1.12）上用，把这一行改成 `11200`，或者不改、直接勾选"加载过期插件"。
3. 启动游戏，在插件列表确认已启用。
4. 小地图旁出现图标即安装成功，不需要任何额外设置。

## 使用方法

### 小地图按钮

- **左键点击** → 打开配置菜单：
  - 点击配置名 → 直接加载该配置
  - "保存当前动作条的布局" → 子菜单选择覆盖已有配置或新建
  - "导出配置为字符串" → 子菜单选择配置，弹出窗口并自动全选字符串
  - "从字符串导入..." → 打开窗口，粘贴字符串后点"导入"
  - "删除一个布局" → 子菜单选择要删除的配置
- **右键拖动** → 按钮绕小地图旋转定位（位置自动保存）

### 斜杠命令

```
/abprofile 保存 <配置名>     # 把当前动作条和按键绑定存成配置
/abprofile 加载 <配置名>     # 加载配置（完全覆盖当前动作条和按键绑定）
/abprofile 删除 <配置名>     # 删除配置
/abprofile 列表             # 列出当前角色的所有配置
/abprofile 对比 <配置名>     # 把当前动作条跟该配置逐槽比一遍，列出差异
/abprofile 导出 <配置名>     # 生成便携字符串并全选（含按键绑定，可跨角色/账号）
/abprofile 导入             # 打开窗口，粘贴便携字符串导入成配置（含按键）
/abprofile debug            # 诊断输出开关（打印扫描/写入/比对的槽位差异）
```

`/abprofile`（不带参数，或命令名后多打了空格）会打印命令提示；`/abprofile help`、`/abprofile ?`、`/abprofile 帮助` 也可以，看不懂的命令同样会打印提示，而不是静默无反应。

## 目录结构

```
ActionBarProfiles/
├── ActionBarProfiles.toc     # 插件清单（元数据、加载顺序、保存变量声明）
├── ActionBarProfiles.xml     # 界面布局（小地图按钮、下拉菜单、Tooltip）
├── ActionBarProfiles.lua     # 全部逻辑代码
├── Images/
│   └── abp.tga               # 小地图按钮图标
├── ActionBarProfiles.lua.bak-autosave  # 旧的"自动保存版"备份，可删
└── README.md
```

## 文件说明

### ActionBarProfiles.toc

| 字段 | 值 | 说明 |
|------|-----|------|
| Interface | 30300 | 3.3.5 接口版本（乌龟服 1.12 改回 `11200`，或勾选"加载过期插件"） |
| Title | [辅助]动作条保存 | 插件标题 |
| SavedVariables | `ABP_Layout`, `ABP_ButtonPosition` | 配置数据 + 小地图按钮角度 |
| 加载顺序 | lua 在前，xml 在后 | 先定义逻辑，再构建界面 |

### ActionBarProfiles.xml

1. **ActionBarProfiles_IconFrame**（按钮，父级 Minimap）：小地图图标；左键弹菜单，右键拖动定位。
2. **ABP_DropDownMenu**（继承 UIDropDownMenuTemplate）— 主交互菜单。
3. **ABP_Tooltip**（独立 GameTooltip）— 保存/加载时用来**探测**动作与物品名称（非展示用途）。
4. **ABP_PortableFrame**（DialogFrame 背景 + 滚动编辑框）— 便携字符串的导出/导入窗口，导出时自动全选，导入按钮触发 `ABP_Portable_Import`。

## 核心数据模型

```lua
ABP_Layout = {
    ["<角色名> of <服务器>"] = {
        ["<配置名>"] = {
            spells = {},       -- [动作槽位] = { name = "技能名", rank = "等级" }
            macros = {},       -- [动作槽位] = 宏名称
            items  = {},       -- [动作槽位] = 物品名称
            macroBodies = {    -- [宏名称] = { body = 宏体, icon = 图标贴图, perchar = "1"/"0" }
                ["宏名"] = { body = "/cast 火球术", icon = "Interface\\Icons\\Spell_Fire_Fire", perchar = "1" },
            },
            bindings = {       -- [绑定命令] = { 主键, 副键 }
                ["ACTIONBUTTON1"] = { "1", "SHIFT-1" },
                ["MULTIACTIONBAR1BUTTON1"] = { "Q" },
            },
        },
    },
}

ABP_ButtonPosition = <number>   -- 小地图按钮角度（0~360）
```

数据按 **角色 → 配置名 → 三种类型** 三层组织。键使用 `角色名 of 服务器名` 实现角色隔离。

## 核心工作流程

### 保存 `ABP_SaveProfile(profileName, silent)`

保存是**异步分帧**执行的（真正的扫描/写入由 `ABP_RunSaveJob` 在计时帧里推进），因为一帧内对几十个槽位做 Tooltip + 拾取/放置会明显掉帧。

1. **扫描段**（每帧 6 个槽位）：遍历动作槽——3.3.5 只扫 **1~120**（121 以上是宠物/载具条，排除），1.12 扫 **1~144**
   - 有内容且 `GetActionText` 非空 → 是宏，存 `macros`，同时用 `GetMacroInfo` 读宏体/图标/是否角色宏存进 `macroBodies`
   - 否则判断类型：
     - **3.3.5**：直接 `GetActionInfo(i)` 取类型，不动光标（因此也不会踩到战斗锁定）
     - **1.12**：没有类型接口，用 `PickupAction`/`PlaceAction` + `CursorHasSpell` 探测
   - 名字/等级一律读 Tooltip 第 1 行：
     - 是技能 → 拆成 技能名 / 等级，存 `spells`
     - 是物品 → 读物品名存 `items`
   - 光标上正拿着东西（`ABP_CursorBusy`）时暂停本帧，避免打断你正在进行的拖拽（仅 1.12 需要判断，3.3.5 不动光标）
   - 任务开始时关闭 `autoSelfCast`、扫描结束时还原（只改两次 CVar）
2. **收尾**：**有动作却什么都没读出来的槽位**（Tooltip 读不出来时会这样）→ 沿用上次存档里的内容，宁可保留旧数据也不要把槽位悄悄清空；同时读取当前动作条按键绑定存入 `bindings`；然后写入并提示。

### 加载 `ABP_LoadProfile(profileName)`

1. 校验配置存在性
2. **战斗守卫**：3.3.5 上扫到 `InCombatLockdown()` 为真时不会硬来——记下配置名，脱战（`PLAYER_REGEN_ENABLED`）后自动补做；1.12 没有战斗锁定，此守卫恒为假、行为不变
3. 预处理三张映射表（减少重复 Tooltip 探测）：
   - `spellMap`：由 `ABP_BuildNeededSpellMap` 生成，含 `exact`（技能名+等级 精确键）与 `byName`（只按技能名，仅当存档没记等级时兜底）
   - `equipItemToId`：物品名 → 装备槽位（遍历 1~19 装备位）
   - `bagItemToLoc`：物品名 → 背包/格位（只在装备位找不到的才继续查背包）
4. 按槽位顺序回填（遍历 1~120 / 1~144）：技能 `PickupSpell` → `PlaceAction`；宏优先 `PickupMacro(0, name)`（超级宏），否则 `ABP_EnsureMacro`（按宏名 → 按宏体去重 → 新建）后 `PickupMacro(idx)`；物品先查装备位再查背包。**存档中为空的槽位会被清空**，实现完全覆盖。
5. 回填期间同样临时关闭 `autoSelfCast`
6. **按键绑定**：配置里有 `bindings` 时，先清空当前所有动作条键位，再按存档逐条 `SetBinding`，最后 `SaveBindings` 落盘。存档里没有的动作条旧键位不会残留；若某个键当前被非动作条命令占用，则跳过并报告冲突。老存档没有 `bindings` 字段时不碰当前按键。
7. 报告放回 / 清空数量、恢复的键位数与"没能恢复"清单（含原因），并安排 **3 秒后的自检**（`ABP_StartVerifyJob` → `ABP_ReportVerify`）

### 便携字符串 `ABP_BuildPortableString` / `ABP_ImportFromString`

- **导出**：`ABP1:` + Base64( 一串长度前缀字段 )。字段依次是版本号（当前为 `2`）、配置名，然后是技能 / 宏 / 物品 / 按键四段（每段先给数量，再按槽号或命令名升序逐条给字段）；宏段额外带宏体、图标贴图、是否角色宏，按键段带命令名、主键、副键。
- **导入**：校验前缀 → Base64 解码 → 逐字段校验（netstring 长度、各段数量、槽号范围）→ 只写入 `ABP_Layout`，**不立刻改动作条或按键**；槽号超出本客户端上限（3.3.5 为 120）的条目会被丢弃并计数。同名配置会弹窗确认覆盖。版本 `1` 的老字符串仍可导入，只是不会带按键数据。
- **安全**：全程不使用 `loadstring`，字符串只被当作纯数据解析；按键段只接受 `ACTIONBUTTON`、`MULTIACTIONBAR*BUTTON`、`BONUSACTIONBUTTON` 三类命令，避免导入字符串把任意命令绑到键上；损坏、截断、版本不符都只报错，不会执行任何代码。

## 函数清单

### 公共 API（暴露为全局）

| 函数 | 作用 |
|------|------|
| `ABP_OnLoad` | 注册 `VARIABLES_LOADED` 与斜杠命令 |
| `ABP_OnEvent` | 分发事件：`VARIABLES_LOADED` 做初始化；`PLAYER_REGEN_ENABLED`（仅 3.3.5 注册）补做被战斗推迟的加载 |
| `ABP_SaveProfile` | 保存配置（**异步**：只创建分帧任务；`silent` 静默） |
| `ABP_RunSaveJob` | 分帧推进任务（计时帧每帧调用） |
| `ABP_StartVerifyJob` | 启动"只扫不写 + 与配置比对"的自检 |
| `ABP_ReportVerify` | 自检结果：一致 / 差异清单 |
| `ABP_LoadProfile` | 加载配置（完全覆盖 + 加载报告 + 安排自检；战斗中自动推迟） |
| `ABP_BuildPortableString` | 把某配置编码成 `ABP1:` 便携字符串（配置不存在时返回 nil + 原因） |
| `ABP_ImportFromString` | 解析便携字符串并写入 `ABP_Layout`；同名配置弹窗确认覆盖 |
| `ABP_Portable_ShowExport` / `ABP_Portable_ShowImport` | 打开导入/导出窗口（导出时自动全选字符串） |
| `ABP_Portable_Import` | 导入按钮回调：读取窗口文本、调用 `ABP_ImportFromString`、失败时原地提示 |
| `ABP_ListProfiles` / `ABP_RemoveProfile` | 列表 / 删除配置 |
| `ABP_SlashCommand` / `ABP_PrintHelp` | 斜杠命令分发 / 命令提示 |
| `ABP_OnUpdate` | 计时帧驱动（推进分帧任务与自检） |
| `ABP_CreateTimerFrame` | 创建计时帧 |
| `ABP_DropDownMenu_OnLoad` | 构建下拉菜单 |
| `ABPButton_UpdatePosition` / `ABPButton_BeingDragged` / `ABPButton_SetPosition` | 小地图按钮定位 |

### 局部辅助函数

| 函数 | 作用 |
|------|------|
| `hasElements` | 判断表是否为空 |
| `ABP_DetectModern` | 探测是否 2.0+ 客户端（`GetActionInfo` 为主，`GetBuildInfo` 兜底） |
| `ABP_Msg` / `ABP_Dbg` | 聊天框输出 / 诊断输出 |
| `ABP_GetTooltipLine1` / `ABP_ComposeSpellKey` | 读 Tooltip 第 1 行 / 组合"技能名 等级"键 |
| `ABP_ForgetSlot` / `ABP_ScanSlot` | 清空某个槽位的分类缓存 / 完整扫描单个槽位 |
| `ABP_CarryOverUnreadable` | 读不出来的槽位沿用上次存档内容 |
| `ABP_DiffSummary` | 汇总两份配置的差异（调试/自检用） |
| `ABP_JobAbort` / `ABP_CursorBusy` / `ABP_TooltipAttach` | 中断任务 / 光标是否忙 / 绑定探测 Tooltip |
| `ABP_InCombat` / `ABP_QueueLoad` | 战斗状态判断 / 记下被推迟的加载（脱战后补做） |
| `ABP_GetPopupEditBox` | 兼容取弹窗输入框（1.12 传确定按钮、3.3.5 传弹窗本身） |
| `ABP_BuildNeededSpellMap` / `ABP_FindItemsInEquipment` / `ABP_FindItemsInBags` | 三张加载用映射表（法术名 exact/byName、装备位、背包） |
| `ABP_GetMacroIconIndex` / `ABP_ReadMacroInfo` | 图标贴图 → 图标序号（懒加载映射）/ 读取宏体、图标、是否角色宏 |
| `ABP_FindMacroIndexByName` / `ABP_FindMacroIndexByBody` | 按宏名找宏序号 / 按宏体找宏序号（去重） |
| `ABP_EnsureMacro` | 宏重建：按名 → 按宏体 → 有空位才 `CreateMacro`；失败返回 nil + 原因 |
| `ABP_IsActionBarBinding` / `ABP_CollectBindings` | 判断是否动作条绑定命令 / 读取当前动作条按键（命令 → 主键、副键） |
| `ABP_ApplyBindings` | 完整覆盖恢复动作条键位：先清空再设置，冲突时跳过并返回说明 |
| `ABP_Base64Encode` / `ABP_Base64Decode` | 标准 Base64 编解码（用 `math.floor` / `2^bits`，不依赖 bit 库） |
| `ABP_PackFields` / `ABP_ReadFields` | netstring 字段流打包 / 读取（`#长度:内容`） |
| `ABP_SortedSlotList` / `ABP_CountEntries` | 槽位升序列表 / 统计条目数量（导出、导入提示用） |
| `ABP_BuildPortablePayload` / `ABP_ParsePortable` | 生成字段流 / 解析字段流并做数量与槽号范围校验 |
| `ABP_StoreImportedProfile`（局部）/ `ABP_PendingImport`（局部变量） | 写入导入结果 / 暂存等待覆盖确认的解析结果 |

## 常量与配置项

| 常量 | 值 | 说明 |
|------|-----|------|
| `MAX_ACTIONS` | 144 | 1.12（乌龟服）遍历的最大动作槽数 |
| `WOTLK_MAX_ACTIONS` | 120 | 3.3.5 玩家动作槽上限（121 以上是宠物/载具条，排除） |
| `ABP_IS_MODERN` | 运行时探测 | 是否 2.0+ 客户端（3.3.5 为 true，1.12 为 false） |
| `ABP_MAX_SLOTS` | `ABP_IS_MODERN` 决定 | 实际遍历上限：3.3.5 取 120，1.12 取 144 |
| `ABP_JobSlotsPerFrame` | 6 | 保存任务每帧处理的槽位数（越小越不卡） |
| `ABP_ScanOnlySlotsPerFrame` | 3 | 自检任务每帧处理的槽位数 |
| `ABP_ButtonRadius` | 78 | 按钮绕小地图旋转半径 |
| `ABP_ButtonPosition` | 默认 60 | 按钮角度持久化变量 |
| `CMD_SAVE/LOAD/REMOVE/LIST/CHECK/EXPORT/IMPORT/DEBUG` | 保存/加载/删除/列表/对比/导出/导入/debug | 中文斜杠命令关键字 |
| `ABP_PORTABLE_TAG` | `"ABP1:"` | 便携字符串前缀（用于快速识别与拒绝无关文本） |
| `ABP_PORTABLE_VERSION` | `"2"` | 便携字符串格式版本；`2` 增加按键段，导入时仍接受 `1` |
| `ABP_BINDING_PATTERNS` | 3 个模式 | 只认 `ACTIONBUTTON*`、`MULTIACTIONBAR*BUTTON*`、`BONUSACTIONBUTTON*` |

## 技术要点与注意事项

1. **依赖客户端的 Tooltip 作为"数据探测仪"**：名字与等级一律通过向 `ABP_Tooltip` 注入动作/物品并读取文本行来获取。3.3.5 上"类型"改用 `GetActionInfo` 直接获取，但名字仍走 Tooltip（两个客户端表现一致）；1.12 无原生 API，全部靠 Tooltip。
2. **`CursorHasSpell` 探测法（仅 1.12）**：1.12 没有类型查询接口，只能通过拾取再放回动作槽判断是否为法术，期间主动关闭 `autoSelfCast` 以避免干扰（只改两次 CVar，不逐帧改）。3.3.5 改用 `GetActionInfo`，不动光标。
3. **宏兼容双路径**：`GetSuperMacroInfo`（超级宏）与 `GetMacroIndexByName`（普通宏）双路回退（超级宏是乌龟服专有，3.3.5 上自动落到普通宏路径）。加载时优先尝试 `PickupMacro(0, name)`，失败才走 `ABP_EnsureMacro` 重建。
4. **加载的限制**：
   - 技能必须是**法术书里能找到的同一个 技能名（+ 等级）**；洗点、没学过、物品给的技能放不回去（会在"没能恢复"清单里说明）。若存档里没记等级（3.3.5 上 Tooltip 读不到等级时会出现），会退化为"只按技能名"匹配。
   - 物品必须还在**背包或装备位**上；放银行、卖掉、用完了就恢复不回去。
   - **姿态 / 奖励动作条**：保存的是当时奖励页的内容。3.3.5 的奖励页对应 **73~108 槽（页 7~9）**，换个姿态 / 形态后再加载会写进当前生效的那一页。
5. **性能**：保存/自检都是分帧任务（每帧 3~6 个槽位）；3.3.5 判类型不动光标，比 1.12 更轻。插件不注册任何动作条/退出事件，不挂钩 `PlaceAction`/`Logout`/`Quit`，平时完全不做事（计时帧每帧只做一次极轻量的判断）。
6. **安全序列化（无 `loadstring`）**：便携字符串是 `ABP1:` + 标准 Base64 + netstring（`#长度:内容`）字段流。解析只做字符串切分与数字校验，从不把输入当代码执行；前缀不符、Base64 非法、长度不足、段数量不符、版本不符都会被明确拒绝。宏体里的中文、换行、`|`、`;`、`#`、`\`、引号都因长度前缀而无需转义。
7. **宏重建的边界**：导出时把宏体、图标贴图、是否角色宏一起写入 `macroBodies`（老存档没有这段数据时，导出会现场读取本机同名宏）。加载/导入时按**宏名 → 宏体 → 新建**的顺序查找，已有同宏体的宏直接复用、不改名也不删除；只有宏位不足时才放弃并在"没能恢复"清单里写"没有空余的宏位"。不再像旧实现那样改名后重复建宏。
8. **按键绑定的范围与冲突**：绑定记录的是动作条按钮命令（`ACTIONBUTTON1~12`、`MULTIACTIONBAR*BUTTON*`、`BONUSACTIONBUTTON*`），不是动作槽号，所以主条翻页时同一组键位仍然有效。加载时按"完整覆盖"处理：先清掉当前所有动作条键位，再逐条设置存档里的键；如果某个键当前被非动作条命令（跳跃、聊天等）占用，则跳过并报告冲突，不会强行抢键。老配置没有 `bindings` 字段时完全不碰当前按键。
9. **不包含动作条外观布局**：按钮位置、数量、分页、缩放属于动作条插件（Bartender4、Dominos 等）自己的数据，本插件不读取也不还原，只保存按钮上的动作和按键。

## 多版本支持（3.3.5 / 1.12）

同一份代码同时支持 **3.3.5（WotLK）** 与 **1.12（乌龟服）**，加载时自动探测客户端，无需维护两份文件。

**探测方式**：`GetActionInfo` 是 2.0+ 才有的函数，拿它当"新客户端"特征最可靠；取不到时用 `GetBuildInfo()` 的主版本号（≥ 2）兜底。探测结果存入 `ABP_IS_MODERN`，并据此决定槽位上限 `ABP_MAX_SLOTS`。

| 行为 | 3.3.5（WotLK） | 1.12（乌龟服） |
|------|----------------|----------------|
| `.toc` 的 `## Interface` | `30300` | `11200`（或勾选"加载过期插件"） |
| 遍历的动作槽 | 1~120（121+ 是宠物/载具条，排除） | 1~144 |
| 槽位类型判定 | `GetActionInfo(i)`，不动光标 | `PickupAction` + `CursorHasSpell` 探测 |
| 名字 / 等级 | 读 Tooltip（同左） | 读 Tooltip |
| 战斗中加载 | 被 `InCombatLockdown()` 拦截，记下配置、脱战后自动补做 | 无战斗锁定，立即执行 |
| 超级宏 | 无（自动落到普通宏路径） | `GetSuperMacroInfo` / `PickupMacro(0, name)` |
| 宏重建 | `CreateMacro`（普通宏，上限由客户端决定） | `CreateMacro`（普通宏；超级宏仍走原生路径） |
| 按键绑定 | 枚举 `GetNumBindings` / `GetBinding` 读取 | 有枚举接口就枚举，否则按已知命令逐个查 `GetBindingKey` |
| 便携字符串 | `ABP1:` 格式一致，导入时按 120 槽上限裁剪 | `ABP1:` 格式一致，导入时按 144 槽上限裁剪 |
| 姿态 / 奖励动作条 | 73~108 槽（页 7~9） | 61~72 槽 |

**结论**：1.12 上的旧行为完全保持不变（走旧探测分支）；3.3.5 上改用原生接口，更快、更稳、也不动光标。**注意**：本插件目前仅在 3.3.5 客户端内做过源码级验证（对照 Bartender4 / AckisRecipeList 的 API 用法），尚未在真实游戏内实测加载。

## 关于"自动保存版"

`ActionBarProfiles.lua.bak-autosave` 是**移除自动保存逻辑之前**的完整备份（含改动后自动保存、退出/登出补存、缓存预热、退出补存记录等）。游戏不会加载它（不在 `.toc` 里）。

- 想彻底干净：直接删掉这个文件。
- 想回退：把它改名回 `ActionBarProfiles.lua`（覆盖当前文件），并把 `.toc` 的 `## SavedVariables:` 改回 `ABP_Layout, ABP_ButtonPosition, ABP_Enabled, ABP_Active, ABP_ExitLog, ABP_ExitState`。
