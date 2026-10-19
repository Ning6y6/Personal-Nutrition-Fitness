# OPT-12 食品导入规则与来源复核

日期：2026-10-17。配套[实施与验收方案](OPT12_FOOD_SEARCH_PLAN.md)。状态：**2026-10-18 用户已随 OPT-12 方案批准本规则，冻结为 `food-import-cofid-2021-v1`；不改 Schema 或新增健康规则。后续完成状态以交付证据为准。**

## 1. 对本轮复核的处理

同意采用 GOV.UK CoFID 2021 原始 Excel 为主要来源、在本地整理中文搜索键；商业 API 暂缓，Open Food Facts 留到条码／标签扫描切片。不同库不拼成没有口径的“统一营养真值”。

需要更正／限定的事实如下；“未核实”只表示现有证据不足，不推断服务不存在或数据错误。

| 项目 | 2026-10-17 核查结论 | 对本片的影响 |
| --- | --- | --- |
| FN-NBRI / CoFID API | Quadram 官方团队提供的真实服务；先前称其第三方不准确。API 软件 v2.2.0／2026 不代表营养库变成 2026 版，技术文档底层仍为 2021；API 的 CC BY-NC-SA 与 GOV 原始 Excel 的 OGL 分开 | 使用原始 OGL 文件，不用 API 或估补缺值的 Food Labelling 数据替代原表 |
| USDA | 官方当前下载表 Foundation 与 Branded 已为 **04/2026**，12/2025 位于历史表；SR Legacy 为最终 04/2018 | 不把 2025-12 写成当前最新版；USDA 保留后续补源候选地位 |
| TFDA | 官方页明确长表字段与政府开放授权；本轮元数据更新为 2026-10-05，不能据此叫营养库 2026 版。用户复核提供的“2016／2,076／94、2020文件”尚未通过本轮实际原文件独立证实 | 后续抽样记录真实文件、版本与时间；元数据时间和数据分析／发布年分开 |
| Open Food Facts | 当前官方文档读取 15 次／分钟／IP、搜索 10 次／分钟；禁止把搜索 API 用于边输入边搜索。需自定义 User-Agent，开发测试用 staging，大批量使用导出。数据库、内容与图片许可分开 | 不用于本片搜索。未来按当时文档核查，不能继续引用旧的 100 次读取限流或假定图片免费无条件使用 |
| 中国大陆／香港 | 公开营养查询站不是已证实的开放批量数据库；此前“中国食物成分数据中心”的机构名未核实，应撤回。香港有 Excel，但个人非商业参考及禁止未经授权转载的限制不能忽略 | 不抓取、抄录受限整库或版权书作为可分发种子来源 |
| OpenNutrition | 官方明确用 LLM 推导缺失乃至整套营养，并承认来源归属缺口；不是只用 AI 改善搜索 | 不作正式数值主源，不能让生成值冒充权威分析值 |
| SG FoodID | 专用许可允许商业／非商业使用和改编分发，但有署名、许可链接、无背书及第三方权利等边界；网站素材条款与数据条款不同 | 值得抽样；正式纳入前核逐项来源、更新日期和许可例外。没发现公开批量／API 文档不等于证明没有 |
| MyFCD | 当前可读详情显示 2026-06-23 发布日期，不能凭页脚 2015 判为停更；本轮未找到可确认的整库再使用授权／批量 API | 记录为可访问、授权待核查，暂不纳入；不写“无人维护／不可用” |
| 英国外卖 | 英格兰法规适用于符合范围且至少 250 人的企业，核心是可食用非预包装餐饮热量。±20% 属实施指导中对变异的处理，不能写成所有餐食的法定精度保证 | 菜单 kcal 只能作每份证据，不能补造整套宏量营养；公开菜单也不等于取得整品牌数据库再分发许可 |

主要核查链接：[Quadram 官方说明](https://quadram.ac.uk/blogs/how-our-food-and-nutrition-team-are-opening-up-uk-nutrition-information-through-new-digital-tools/)、[API 技术文档](https://fnnbri.quadram.ac.uk/wp-content/uploads/2026/06/CoFID_API_Technical_Documentation.pdf)、[USDA 当前下载表](https://fdc.nal.usda.gov/download-datasets/)、[TFDA 数据集](https://data.gov.tw/dataset/8543)、[OFF 当前 API 文档](https://openfoodfacts.github.io/openfoodfacts-server/api/)、[OFF 许可说明](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/)、[大陆公开查询](https://nlc.chinanutri.cn/fq/)、[香港查询与声明](https://www.cfs.gov.hk/english/nutrient/)、[OpenNutrition About](https://www.opennutrition.app/about)、[MyFCD 当前详情](https://myfcd.moh.gov.my/myfcdcurrent/index.php/site/detail_product/R101061/0/10/-1/0/0/)、[英格兰实施指导](https://www.gov.uk/government/publications/calorie-labelling-in-the-out-of-home-sector/calorie-labelling-in-the-out-of-home-sector-implementation-guidance)。

德国 BLS、法国 Ciqual、瑞士、加拿大 CNF、澳洲 AFCD、日本成分表等开放库继续列为未来候选，不因本片扩大到多库集成；选用时重新冻结具体文件和许可，而不是沿用网页摘要的“最新版”。商业免费档仍可能限制缓存／永久保存，不能仅凭免费资格推断能制作离线库。私人非商业使用也不自动授权抓取、复制整库或向朋友分发；保留未来上架余地是偏好，不替代具体许可条件。[英国版权例外说明](https://www.gov.uk/guidance/exceptions-to-copyright)

## 2. CoFID 文件及规则版本

主源：[GOV.UK CoFID 页面](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid)、[2021 官方指南](https://assets.publishing.service.gov.uk/media/60538e66d3bf7f03249bac58/McCance_and_Widdowsons_Composition_of_Foods_integrated_dataset_2021.pdf)、[官方原始 Excel](https://assets.publishing.service.gov.uk/media/60538b91e90e07527df82ae4/McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021..xlsx)。文件名确为 `2021..xlsx`，不是排版错误。本轮公开 Excel 在内存中检查了表头／示例，未写入项目或用户数据库。

实施时登记：来源机构、dataset release、下载 URL、获取日期、原文件名／SHA-256、指南版本、许可 URL／署名、工作表／列代码与单位、转换规则版本、中文审核版本及发布清单 SHA-256。数据版本、API 软件版本、网页更新和本地打包日期分别存放。

已批准第一版标识：`food-import-cofid-2021-v1`；不覆盖原工作区尚未整理的 DECISIONS 改动，以本文件及独立交付报告记录批准与实现。源文件更新或算法变化不能只覆盖旧文件和沿用同一版号。

## 3. 基准、原值和缺失值

### 3.1 每个数值都带基准

导入中间资料至少表达：来源食品键、原字段、原始单元格文本、单位、每 100g food／100ml／每份等基准、食品状态、数值或缺失状态、分析定义、转换步骤与版本。

CoFID 指南印刷第 7 页及 `1.1 Notes!A4` 指出酒精饮料按每 100ml；部分脂肪酸表另有每 100g fatty acids，不能当每 100g food。当前餐食和模板仅支持 g：正式可选食品必须有明确的 per-100g-food 基准；没有可靠密度不能把 100ml 除／乘一个猜测值当 100g。液体若来源本身按 100g 报告，可以按质量使用。

每份菜式／菜单热量保留份量和原单位，不以猜测克重或缺宏量填零构造 FoodItem。生熟、带骨／可食部、沥干与干品／复水状态均按源描述保留。

### 3.2 原始状态

| 来源单元格 | 中间状态 | 进入现有 Core 数值的规则 |
| --- | --- | --- |
| 数字 0 | 明确报告为 0 | 保留 0；不混同未知 |
| 非负有限数字 | 有报告值 | 仅做明确单位转换 |
| `Tr` | trace，保留原标记 | 本片沿用计算近似 0 的策略；资料中说明是痕量近似，不能说来源测得精确 0 |
| `N` | 显著存在但无可靠量 | 未知，绝不能填 0 |
| 空白 | 原始空白、数值未知 | 保留 unknown；指南未给出统一空白定义，这里是工程保守规则，不冒充官方解释 |
| 其他文字、负值、NaN／无限 | 未识别或无效 | 阻断并列入核查，不忽略或自动提取一部分 |

`Tr`／`N` 的官方说明位于 `1.1 Notes!A5:A6`。当前 Core 除纤维可选外，能量、蛋白、脂肪、饱和脂肪、碳水、糖、盐均为必需数值；任一必需项 N／空白时，该候选隔离，不能为达到 300 条而填零。AOAC 纤维缺失则传 nil，并继续显示未知／已知小计语义。隔离候选不进入可选择食品数量。

## 4. 字段映射与不得混用的口径

下表字段以实际 2021 Excel 表头为准；列号只作本次核查定位，导入器必须同时验证字段代码与单位，不能假设以后文件列序恒定。

| 目标／保留资料 | CoFID 原字段及位置 | 第一版处理 |
| --- | --- | --- |
| energyKcal | `1.3 Proximates` 的 `KCALS`（M，第2行字段代码）；`KJ` 在 N | 原样保留来源 kcal，不把 kJ 当 kcal，不使用并不存在的 ENERC 列名 |
| protein／fat／sat fat | 同表对应蛋白、总脂肪、饱和脂肪的 per-100g-food 字段 | 用明确字段与单位映射；不得把总脂肪／脂肪酸百分比串列 |
| carbohydrate | `CHO`，可利用碳水、单糖当量 | 保留源值与定义；不与 USDA carbohydrate by difference 混并 |
| sugar | `TOTSUG`（Q），单糖当量，不含寡糖 | 保留此口径，不直接与标签糖重量混并；不能拿 CHO 或总淀粉替代 |
| saltGrams | sodium，源单位 mg／100g | `sodium_mg / 1000 × 2.5`；若别的来源已给盐，不能再次乘 2.5；保留钠原值和计算证据 |
| fibreGrams | `AOACFIB`（Z）；`ENGFIB`／NSP 在 Y | 使用 AOAC；缺值保持 nil，不拿 NSP 填充，不跨库拼出未证实的同一食品 |
| retinol 元资料 | `1.5 Vitamins` H：`RET`，µg | 与当前 FoodItem 分离保存于公开资料；不写成总维 A，也不触发食物医疗判断 |
| 胡萝卜素／总维 A 元资料 | I：`CAREQU` 是 β-胡萝卜素当量；J：`RETEQU` 才是总 RE，均 µg | 分开保留；RETEQU 依 RET 与 CAREQU/6，不把 CAREQU 当总维 A，不改名 RAE、不默算 RAE |
| cholesterol／trans 元资料 | 来源胆固醇字段及 `FODTRANS`（Proximates AT）；保留实际单位 | 资料留存，不新增 Core 健康计算或显示上限 |
| MUFA／PUFA 元资料 | `MONOFOD`（AJ）、`POLYFOD`（AN） | 已含其中反式成分，不再把 FODTRANS 加一遍；cis 字段另行保留定义 |

指南印刷第 10–13 页是能量、碳水、脂肪酸、纤维及维 A 的主要定义，第 16 页讨论标签换算。CoFID KCALS 的方法未加入纤维能量；英欧标签可能按纤维 2 kcal/g 计，**本片不据此重算 CoFID 热量**。各来源总量与自行 4/9/4 重算不完全相等，不用算式强行“修正”原数据。

“CoFID 碳水约除以 1.05 就是标签值”不能作通用导入公式：指南对淀粉、寡糖等有不同处理，淀粉举例除以 1.10，葡萄糖不变。本片保留单糖当量值及口径，未来需要标签化时另定逐成分规则。RE 与 RAE 的胡萝卜素换算不同，不能按字段名字近似合并；跨库 RET 也须逐一核单位、基准和原定义。[NIH 维生素 A 定义](https://ods.od.nih.gov/factsheets/VitaminA-HealthProfessional/)

## 5. TFDA／SG FoodID 抽样要求

- 每源先取涵盖原料、常见熟主食与中式熟菜的代表样本，记录原编码／名称、状态、必需营养完整性、纤维定义、计量基准、版本／更新字段、许可与出处。记录能找到和找不到的食品，不用搜索结果数量当全库规模。
- TFDA 为长表，按原食品码关联各营养字段；检查重名、重复项、样本数／标准差、每 100g 与每单位重，不能按食品中文名简单 pivot 后覆盖。繁体转简体后仍保留原名，人工核对不同食品同名问题。
- SG FoodID [About Our Data](https://pphtpc.hpb.gov.sg/web/sgfoodid/about-our-data)区分 Borrowed、Derived、Lab Analysis、NIP；分别保留，不能一概描述为新加坡实测。Dash／Trace／0 按其定义处理，不套 CoFID 的 N。逐项记录 source-of-data 和 last-updated。
- SG FoodID 专用[许可 PDF](https://file.go.gov.sg/termsofuse-hpbsgfoodid.pdf)第 10–11 条允许数据多种商业／非商业使用，但排除其无权许可的第三方权利，要求醒目署名和最新许可链接。对借入来源核查这一例外；参考其示例保留访问日期和 as-is 声明，不暗示 HPB 背书。[FAQ](https://pphtpc.hpb.gov.sg/web/sgfoodid/faq)还邀请研究／商业项目联系讨论。本次不联系、不申请、不批量抓取。
- 抽样若仍不能确认可复现下载、数据版本、完整必需字段或使用权，结论为暂缓纳入。已认可抽样不等于已批准整库接入。

## 6. 清真、异维 A 酸、LDL 与按锅称重的边界

这些是目录整理和后续路线的输入，不能让食物来源字段变成未批准的自动健康裁决。

| 需求 | 本片可以做 | 本片不据此推导 |
| --- | --- | --- |
| 清真 | 人工审核新增候选，明确猪肉／含酒排除；不明明胶／混合菜隔离；保留证据与理由 | 无认证不等于 haram；明胶不必然来自猪；通用鸡肉／牛肉营养不证明具体采购品 halal |
| 认证查询 | 记录 HMC／JAKIM 的公开查询存在，尚未找到本片可确认的公开开发 API／再分发授权 | 不写“没有 API”的绝对结论，不复制认证站整库，不给贡献者 halal 标签认证级可靠性 |
| 异维 A 酸 | 留存可取得的 RET／定义／单位，供未来批准的规则研究 | 不给所有富含维 A 食物自动禁食标记，不把补充剂规则扩大为食物阈值 |
| LDL | 留存饱和脂肪／纤维及可得胆固醇、trans 原始证据 | 不按某一种营养素自动判单个食品安全／危险；不自动生成个人医疗目标 |
| 按锅称重 | 300 项优先生料，说明真实生熟状态 | 生原料重量不能当成熟菜本人食用重量；全锅分份属于 OPT-15／16，尚未实施 |
| 英国外卖 | 记录有权使用的菜单热量、份量和来源作为候选证据 | 不能由一份 kcal 推出每 100g 或缺失宏量；独立中餐菜不能借相似英文名当同一配方 |

OFF 确有贡献者录入的 halal 标签，因此“所有食品库都没有清真标记”过于绝对；本片不依赖这种标签作认证。[OFF API](https://openfoodfacts.github.io/openfoodfacts-server/api/)、[HMC 明胶说明](https://halalhmc.org/news/gelatine-statement/)、[HMC 未认证不等于 haram](https://halalhmc.org/faqs/does-hmc-consider-non-hmc-certified-meat-and-poultry-to-be-haram/)、[JAKIM 查询](https://www.islam.gov.my/en/law-legal/halal-status-check)

现有 `SupplementRuleEngine` 是补充剂标签规则，不是食物视黄醇阈值。药品说明提醒避免相关维 A 补充剂，不能据此自行新增动物肝脏等食品自动禁令；医学规则另需明确范围、权威依据、版本与批准。[NHS 异维 A 酸资料](https://www.nhs.uk/medicines/isotretinoin-roaccutane/)、[药品患者说明](https://www.medicines.org.uk/emc/product/10555/pil)、[NHS 降胆固醇资料](https://www.nhs.uk/conditions/high-cholesterol/how-to-lower-your-cholesterol/)

## 7. 身份、中文审核与署名

- 稳定来源键由 provider／dataset release／原编码组成；正式 UUID 在发布清单冻结，不使用每次启动随机 UUID，也不依赖可能变化的中文名。旧 12 项显式兼容映射保留原 UUID 和内容，不新增同食品副本凑数。
- 人工审核简体名、别名、生熟、部位、带皮／去皮、可食部等；不将猪肉改名为泛称“肉”，不把不明混合菜译成清真菜，不用 LLM 生成营养值。多音字拼音键与例外随目录版本冻结。
- 公共资料与用户食品关联前核验指纹；不能通过同 UUID 把自改记录显示成来源原值。无法确认来源的本地记录保留并说明资料未核实。
- 设置增加最小只读“数据来源与许可”：来源机构／数据版本、原始 URL／许可 URL、署名、翻译／节选／Tr近似／盐换算等修改说明。许可原文与中文解释分开；不使用数据提供者标志暗示背书。
- CoFID 按发布者要求署名并附 OGL 链接；精确署名文字从原文件／发布页核定后冻结。若未来用 CC BY、TFDA、SG FoodID，分别附其要求；不能用一个 OGL 总标题覆盖全部来源。OFF 图片许可另属扫描切片，不下载图片来扩大本次范围。[OGL v3](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)

## 8. 导入前必须通过的检查

1. **身份与许可**：原文件 SHA、真实数据版本、许可和原编码可回溯；API 版号不当数据年份；来源别名不能跨生熟／基准。
2. **状态与单位**：数值 0、Tr、N、空白各有独立 fixture；100g food、100ml、每份、100g fatty acids 混入时阻断；单位缺失不能猜。
3. **数值**：至少覆盖 RET／RE 区分、AOAC 缺失而 NSP 有值、钠 400mg → 盐 1g、已有盐不重复换算、kJ 不当 kcal、反式不重复求和、保留原 KCALS／CHO。容差仅为浮点／源精度核对，不能当医学阈值。
4. **完整性与计数**：任一必需项未知不得发布；AOAC 未知保持 nil；目录至少 300 个真实不同食品，明确原有 12 项是否已计入、分类覆盖、隔离理由和未解决缺口。
5. **旧安装与恢复**：12 项逐字段不变；新目录追加失败原库不变；重复追加／重开／恢复后不重复、不覆写；同 ID 异内容保留本地并报告。
6. **公开证据与隐私**：审核记录仅含公共来源与合成 fixture；不存用户餐食、健康导出、私人照片、API key 或签名资料。扩展营养存公共目录不意味着已写入用户私库，更不意味着已批准新健康提醒。

以上检查在实现前冻结为测试与审核要求；最终测试数量、通过率和真实条目清单在实施交付报告记录。本次文档不预填“导入通过”或“300 项完成”。
