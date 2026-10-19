# OPT-12 正式目录审计

日期：2026-10-18。目录版本 `cofid-2021-zh-v1`，导入规则 `food-import-cofid-2021-v1`，代码基线 `6990010`。本文件只记录公共目录与 Python 导入验证；SwiftData、Core、App 单元、模拟器、构建及真机验收由本片总报告分别记录，不能用这里的成功代替这些门禁。

## 结果与来源

正式可选择目录 **357 项真实食品：原12项 + 345项新增**。别名和拼音不计数量；没有测试合成食品、跨库拼值或同编码副本凑数。源名中明确包含 `raw`／`uncooked` 的有 **212 项**，其余按原料、干品、可食部和烹调信息分别保留，不据此推定可生食。分类是现有 FoodCategory，蔬果沿现有 mixed_meal 适配，不新增领域枚举。

| 现有分类 | 数量 |
| --- | ---: |
| `staple_grain` | 47 |
| `mixed_meal` | 133 |
| `protein_main` | 108 |
| `oil` | 14 |
| `sauce` | 10 |
| `snack_dessert` | 31 |
| `beverage` | 14 |

主源：[Public Health England / GOV.UK CoFID 2021](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid)；[官方 Excel](https://assets.publishing.service.gov.uk/media/60538b91e90e07527df82ae4/McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021..xlsx)；[官方2021指南](https://assets.publishing.service.gov.uk/media/60538e66d3bf7f03249bac58/McCance_and_Widdowsons_Composition_of_Foods_integrated_dataset_2021.pdf)。获取日期2026-10-18。源文件 `McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021..xlsx` 为4,629,542 bytes，只放临时目录，没有加入Git。

- 原 Excel SHA-256：`436e9445ef2adb2a75f3d7edd51302de3adad25385f9795fc94ba58bd030e97d`。
- 发布目录 SHA-256：`dfa65f09417aca70f4a83306b4869b603524d466a88f4962f0eaf54e5e10d36d`。
- 冻结整理表 SHA-256：`7dc585069fdfddbc257f71793b795f3d758011194be47cdb9348958a4f51a208`。
- 许可：[Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)。
- 署名：Public Health England (2021). McCance and Widdowson’s The Composition of Foods Integrated Dataset (CoFID). Contains public sector information licensed under the Open Government Licence v3.0.
- 修改说明：节选、简体名／别名／拼音、Tr计算近似0、钠换算盐；保留原始单元格和定义。未使用 FN-NBRI API／Food Labelling 估补库，也未重算 CoFID KCALS／CHO／糖。

## 源缺陷、隔离和已知缺口

官方 Proximates 有2,887行、2,886个唯一食品编码：**13-669在第55行烤茄子和第2827行生西洋菜重复**。导入器把这两行同时隔离，不按编码后写覆盖前写，也不靠中文名猜哪个正确。跨表读取同时核对来源行、编码与原英文名；脚本自测另用合成重复码验证这一分支。

在排除这两行后的2,885个唯一身份中，359项缺少至少一个现有Core必需字段；2,526项必需字段可构造数值并不代表它们都获准选择，其中仍有猪肉、酒精、配方和其他本片未整理条目。不将这些数计为已批准目录规模。按字段的缺失数量见 manifest，互相有重叠，不能相加当食品数。

另将原候选 **11-1045 Flour, corn，第1164行**隔离：描述只有6 samples／5 products，未明确玉米面与英国cornflour／淀粉的品类区别。本轮不据营养比例反推定义，不给它套“玉米面”别名，未进入正式357项。该四位后缀本身合法，不是编码格式错误；正式目录仍包含11-1129等四位后缀。

明确猪肉、含酒和来源不明明胶／复杂配方不纳入新增目录；同一食品的生熟、部位、皮／去皮、干／泡发保持独立码。通用牛羊鸡肉数据不证明实际采购品清真认证。本片没有新增认证或健康自动裁决。

目录纤维 nil 共 **168项**；AOAC未知、NSP已知仍保留nil，不把NSP当AOAC。扩展原值共保留 trace `658`、N `124`、空白 `1058`个单元格；这些计数包含RET／脂肪酸等扩展字段，不是“必需项未知仍发布”的食品数。

## 旧12项保护和审核边界

旧12项完整保留原UUID、名称、分类、单位、全部营养数值（含6项纤维nil）及原source文本。整理表冻结基线6990010的12项值；导入器对规范化完整快照SHA进行校验，修改任意字段会阻断，不只核对UUID。原始源值仍独立存于rawNutrients，legacyNotes注明兼容策略。本轮与新投影比较没有数值差异，但不能据此授权将来覆盖用户记录或修补旧纤维。

逐项对照了全部中英文名、食品状态、别名、拼音和原编码；第二位开发代理完整复核初版358项，修正unsweetened／cress／Chard／米饭／鸡四分体和拼音歧义，并隔离corn-flour候选。这里是**两轮开发核对，不是独立人类营养审计或清真认证**。用户最终目录抽查、VoiceOver和真实使用验收仍由总报告记录，不能写成已经人工签字。

系统辅助拼音专项覆盖357个去括号状态主名、118个别名、432个冻结键：用macOS Foundation `toLatin`／`stripDiacritics`生成常规首字母，仅作疑点发现，逐项开发核对语境读音和短键。修正11-878的`ablysfm`为`ablayshfm`、14-159的`glytg`为`jlytg`；此前11-879已改为`ablamf`。Foundation把“长粒”读成zhang、“茄”读成jia时，不以机器输出覆盖正确的chang／qie语境读音。这是开发代理的语言核对，不代表独立人类认证。

其余14个非完整主名键是有意义的食材短键／前缀，明确保留：13-297 `jcm`（芥菜苗）、13-348 `cgl`（春甘蓝）、13-089／13-661 `lbd`（绿扁豆）、14-362 `pg`（苹果）、14-159 `tg`（甜瓜）、14-372 `lz`（李子）、14-870 `bdm`（巴旦木）、11-895／11-894 `ydbb`（印度薄饼）、11-886 `djbmf`（低筋白面粉）、18-293 `jtsft`（鸡腿四分体）、18-295 `jcsft`（鸡翅四分体）、16-382 `nyr`（鲶鱼肉）。短键不省略界面显示的生熟、部位和来源限定，不用短键将不同食品合并。

foodState只展示食品有意义的生熟和可食部信息；兼容／种子保留说明放legacyNotes。没有将数值自动生成成功当作中文名审核，亦未让LLM生成营养值。完整词条见下表，可直接复核每个来源名与搜索键。

## 字段与验证

字段、列位置、单位、基准及指南印刷页数全部冻结在 `data/food-catalog/catalog-manifest-v1.json` 的sourceColumns。核心映射：KCALS、PROT、FAT、SATFOD、CHO、TOTSUG、NA；AOACFIB可选；RET／CAREQU／RETEQU、ENGFIB、FODTRANS／MONOFOD／POLYFOD、CHOL原值另存。每100g脂肪酸和100ml／每份不进入当前g计餐适配。

只允许明确单位换算：钠mg÷1000×2.5为盐g；Tr只作计算近似0但保留原token；N／空白必需项阻断，AOAC未知为nil。能量取KCALS，不取KJ、不套4/9/4；CHO与TOTSUG保留单糖当量、不统一÷1.05；RE不是RAE；反式不在MUFA/PUFA上重复累加。

本轮实际运行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_import_cofid.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 scripts/import_cofid.py /private/tmp/opt12-cofid-2021.xlsx --check
```

**17个独立Python tests全通过**；从该官方Excel重现目录／manifest逐字节比较通过。自测使用小型合成xlsx，不下载网络、不访问SwiftData或用户库，覆盖0／Tr／N／空白、异常数值、每个必需字段未知、钠盐换算、KJ／宏量不重算、CHO／糖原值、NSP不替代、100ml／每份／100gFA拒绝、单位与代码分离、跨表不匹配、重复编码隔离、拼音、旧12完整快照及核心实际搜索样本。原始Excel外置，复核者需要从以上官方链接自行取得相同SHA文件。

[TFDA／SG FoodID小样本结论](OPT12_SOURCE_SAMPLING.md)独立记录：SG取得3个公开详情，TFDA食品级样本受查询站连接条件限制未取得；均未纳入本目录。

## 完整正式清单

下表的“旧”仅表示原12项兼容，不是营养数据的新旧等级；“行”是官方1.3 Proximates原始行。UUID、完整rawNutrients、来源描述／脚注和逐项字段证据保存在发布JSON，整理表是中文词条的可编辑权威来源，不能手改发布JSON绕过重现检查。

### staple_grain

| 编码／行 | 简体名 | 英文原名 | 状态 | 别名；首字母 | 旧 |
| --- | --- | --- | --- | --- | --- |
| 11-862 / 2357 | 熟长粒白米饭（无盐） | Rice, white, long grain, boiled in unsalted water | 煮熟，无盐 | 熟米饭、米饭；sclbmf, mf, smf | 旧 |
| 11-895 / 1162 | 印度薄饼用棕色面粉 | Flour, chapati, brown | 干面粉 | ；ydbb |  |
| 11-894 / 1163 | 印度薄饼用白面粉 | Flour, chapati, white | 干面粉 | ；ydbb |  |
| 11-896 / 1166 | 鹰嘴豆粉 | Flour, gram | 干豆粉 | ；yzdf |  |
| 11-897 / 1169 | 黑麦粉 | Flour, rye | 干面粉 | ；hmf |  |
| 11-898 / 1170 | 大豆粉 | Flour, soya | 干豆粉 | ；ddf |  |
| 11-887 / 1171 | 高筋白面粉 | Flour, wheat, bread/strong, white | 干面粉 | 面包粉；gjbmf, mbf |  |
| 11-892 / 1172 | 棕色小麦粉 | Flour, wheat, brown | 干面粉 | ；zsxmf |  |
| 11-886 / 1174 | 低筋普通白面粉 | Flour, wheat, white, plain, soft | 干面粉，非自发粉 | ；djbmf |  |
| 11-888 / 1175 | 白色自发粉 | Flour, wheat, white, self raising | 干面粉，含膨松成分 | ；bszff |  |
| 11-889 / 1176 | 全麦面粉 | Flour, wheat, wholemeal | 干面粉 | ；qmmf |  |
| 11-901 / 868 | 库斯库斯（干） | Couscous, plain, raw | 干品，未煮 | 北非小米；ksks |  |
| 11-719 / 1753 | 鸡蛋面（干，未煮） | Noodles, egg, dried, raw | 干面，未煮 | ；jdm |  |
| 11-941 / 1754 | 细鸡蛋面（干面无盐煮熟） | Noodles, egg, fine, dried, boiled in unsalted water | 干面煮熟，无盐 | ；xjdm |  |
| 11-724 / 1756 | 中粗鸡蛋面（干面无盐煮熟） | Noodles, egg, medium, dried, boiled in unsalted water | 干面煮熟，无盐 | ；zcjdm |  |
| 11-942 / 1757 | 粗鸡蛋面（干面无盐煮熟） | Noodles, egg, thick, dried, boiled in unsalted water | 干面煮熟，无盐 | ；cjdm |  |
| 11-725 / 1758 | 细米粉（干米粉无盐煮熟） | Noodles, rice, fine, dried, boiled in unsalted water | 干米粉煮熟，无盐 | ；xmf |  |
| 11-726 / 1889 | 鲜鸡蛋意面（未煮） | Pasta, egg, fresh, raw | 鲜面，未煮 | ；xjdym |  |
| 11-715 / 1890 | 白色鸡蛋意面（干，未煮） | Pasta, egg, white, dried, raw | 干面，未煮 | ；bsjdym |  |
| 11-716 / 1897 | 白色意面（干，未煮） | Pasta, white, dried, raw | 干面，未煮 | 意大利面；bsym, ydlm |  |
| 11-1129 / 1896 | 白色意面（干面无盐煮熟） | Pasta, white, dried, boiled in unsalted water | 干面煮熟，无盐 | ；bsym |  |
| 11-722 / 1898 | 白色意大利细面（无盐煮熟） | Pasta, white, spaghetti, dried, boiled in unsalted water | 干面煮熟，无盐 | 熟意面；bsydlxm, sym |  |
| 11-718 / 1901 | 全麦意大利细面（干，未煮） | Pasta, wholewheat, spaghetti, dried, raw | 干面，未煮 | ；qmydlxm |  |
| 11-723 / 1900 | 全麦意大利细面（无盐煮熟） | Pasta, wholewheat, spaghetti, dried, boiled in unsalted water | 干面煮熟，无盐 | ；qmydlxm |  |
| 11-788 / 2178 | 燕麦片（未强化） | Porridge oats, unfortified | 干品，未强化 | 粥用燕麦；ymp, zyym |  |
| 11-866 / 2337 | 巴斯马蒂糙米（生） | Rice, brown, basmati, raw | 生米，未煮 | ；bsmdcm |  |
| 11-867 / 2336 | 巴斯马蒂糙米饭（无盐） | Rice, brown, basmati, boiled in unsalted water | 煮熟，无盐 | ；bsmdcmf |  |
| 11-868 / 2341 | 全粒糙米（生） | Rice, brown, wholegrain, raw | 生米，未煮 | ；qlcm |  |
| 11-869 / 2340 | 全粒糙米饭（无盐） | Rice, brown, wholegrain, boiled in unsalted water | 煮熟，无盐 | ；qlcmf |  |
| 11-876 / 2346 | 红米（生） | Rice, red, raw | 生米，未煮 | ；hm |  |
| 11-877 / 2312 | 红米饭（无盐） | Red rice, boiled in unsalted water | 煮熟，无盐 | ；hmf |  |
| 11-874 / 2350 | 泰国香米（生） | Rice, Thai fragrant, raw | 生米，未煮 | ；tgxm |  |
| 11-875 / 2349 | 泰国香米饭（无盐） | Rice, Thai fragrant, boiled in unsalted water | 煮熟，无盐 | ；tgxmf |  |
| 11-857 / 2354 | 巴斯马蒂白米（生） | Rice, white, basmati, raw | 生米，未煮 | ；bsmdbm |  |
| 11-858 / 2351 | 巴斯马蒂白米饭（无盐） | Rice, white, basmati, boiled in unsalted water | 煮熟，无盐 | ；bsmdbmf |  |
| 11-878 / 2356 | 阿博里奥意式烩饭米（生） | Rice, white, Italian Arborio risotto, raw | 生米，未煮 | ；ablayshfm |  |
| 11-879 / 2355 | 阿博里奥米饭（无盐水煮） | Rice, white, Italian "Arborio" risotto, boiled in unsalted water | 煮熟，无盐；仅米饭 | ；ablamf |  |
| 11-861 / 2360 | 长粒白米（生） | Rice, white, long grain, raw | 生米，未煮 | 生米；clbm, sm |  |
| 11-865 / 2361 | 布丁用白米（生） | Rice, white, pudding, raw | 生米，未煮 | ；bdybm |  |
| 11-872 / 2363 | 菰米（生） | Rice, wild, raw | 生米，未煮 | 野米；gm, ym |  |
| 11-873 / 2362 | 菰米饭（无盐） | Rice, wild, boiled in unsalted water | 煮熟，无盐 | ；gmf |  |
| 11-023 / 2400 | 西米（生） | Sago, raw | 干品，未煮 | 沙谷米；xm, sgm |  |
| 11-903 / 2521 | 粗粒小麦粉（生） | Semolina, raw | 干品，未煮 | 杜兰粗面粉；clxmf, dlcmf |  |
| 11-027 / 2679 | 木薯淀粉（生） | Tapioca, raw | 干品，未煮 | ；msdf |  |
| 11-904 / 2832 | 布格麦（生） | Wheat, bulgur, raw | 干品，未煮 | 碎粒小麦；bgm, slxm |  |
| 11-907 / 2833 | 小麦胚芽 | Wheatgerm | 未另标烹调状态 | ；xmpy |  |
| 14-843 / 2292 | 藜麦（生） | Quinoa, raw | 干籽，未煮 | ；lm |  |

### mixed_meal

| 编码／行 | 简体名 | 英文原名 | 状态 | 别名；首字母 | 旧 |
| --- | --- | --- | --- | --- | --- |
| 13-517 / 2730 | 西红柿（生） | Tomatoes, standard, raw | 生 | 番茄；xhs, fq | 旧 |
| 13-318 / 1987 | 青椒（生） | Peppers, capsicum, green, raw | 生 | 绿甜椒；qj | 旧 |
| 13-161 / 59 | 茄子（生） | Aubergine, raw | 生 | ；qz | 旧 |
| 13-146 / 5 | 琼脂（干） | Agar, dried | 干品 | 寒天；qz, ht |  |
| 13-147 / 6 | 琼脂（干品泡发后沥干） | Agar, dried, soaked and drained | 泡发、沥干 | 泡发寒天；qz, pfht |  |
| 13-149 / 14 | 苋菜叶（生） | Amaranth leaves, raw | 生 | 苋菜；xc |  |
| 13-153 / 47 | 洋蓟（生） | Artichoke, globe, raw | 生 | 朝鲜蓟；yj, cxj |  |
| 13-157 / 51 | 芦笋（生） | Asparagus, raw | 生 | ；ls |  |
| 13-164 / 278 | 甜菜根（生） | Beetroot, raw | 生 | 红菜头；tcg, hct |  |
| 13-502 / 454 | 西兰花（生） | Broccoli, green, raw | 生 | 青花菜、绿花椰菜；xlh, qhc, lhyc |  |
| 13-174 / 457 | 紫芽西兰花（生） | Broccoli, purple sprouting, raw | 生 | ；zyxlh |  |
| 13-177 / 462 | 抱子甘蓝（生） | Brussels sprouts, raw | 生 | 孢子甘蓝；bzgl |  |
| 13-582 / 491 | 卷心菜（平均，生） | Cabbage, average, raw | 生，平均值 | 圆白菜、包菜；jxc, ybc, bc |  |
| 13-187 / 492 | 大白菜（生） | Cabbage, Chinese, raw | 生 | 结球白菜；dbc, jqbc |  |
| 13-510 / 494 | 绿甘蓝（生） | Cabbage, green, raw | 生 | ；lgl |  |
| 13-190 / 497 | 紫甘蓝（生） | Cabbage, red, raw | 生 | 红甘蓝；zgl, hgl |  |
| 13-509 / 499 | 白甘蓝（生） | Cabbage, white, raw | 生 | ；bgl |  |
| 13-496 / 541 | 胡萝卜（成熟，生） | Carrots, old, raw | 生，成熟根 | ；hlb |  |
| 13-448 / 544 | 嫩胡萝卜（生） | Carrots, young, raw | 生，嫩根 | ；nhlb |  |
| 13-208 / 551 | 木薯（生） | Cassava, raw | 生 | ；ms |  |
| 13-512 / 574 | 花椰菜（生） | Cauliflower, raw | 生 | 菜花；hyc, ch |  |
| 13-636 / 580 | 芹菜（生） | Celery, raw | 生 | 西芹；qc, xq |  |
| 13-223 / 586 | 瑞士甜菜（生） | Chard, Swiss, raw | 生 | 牛皮菜；rstc, npc |  |
| 13-225 / 736 | 白菊苣（生） | Chicory, pale variety, raw | 生，浅色品种 | ；bjj |  |
| 13-227 / 750 | 佛手瓜（生） | Cho cho, raw | 生 | 合掌瓜；fsg, hzg |  |
| 13-627 / 864 | 西葫芦（生） | Courgette, raw | 生 | ；xhl |  |
| 13-234 / 910 | 羽衣甘蓝（生） | Curly kale, raw | 生 | ；yygl |  |
| 13-240 / 1106 | 苦苣（生） | Endive, raw | 生 | ；kj |  |
| 13-241 / 1122 | 球茎茴香（生） | Fennel, Florence, raw | 生 | ；qjhx |  |
| 13-244 / 1208 | 大蒜（生） | Garlic, raw | 生 | 蒜瓣；ds |  |
| 13-245 / 1215 | 小黄瓜（生） | Gherkins, raw | 生，未腌制 | 酸黄瓜用小黄瓜；xhg |  |
| 13-254 / 1234 | 丝瓜（生） | Gourd, ridge, raw | 生 | 棱角丝瓜；sg |  |
| 13-261 / 1394 | 苤蓝（生） | Kohl rabi, raw | 生 | 球茎甘蓝；pl, qjgl |  |
| 13-624 / 1525 | 韭葱（生） | Leeks, raw | 生 | ；jc |  |
| 13-520 / 1556 | 生菜（平均，生） | Lettuce, average, raw | 生，平均值 | ；sc |  |
| 13-271 / 1592 | 莲藕（生） | Lotus tubers, raw | 生 | 藕；lo |  |
| 13-274 / 1616 | 大西葫芦（生） | Marrow, raw | 生，marrow | ；dxhl |  |
| 13-293 / 1732 | 平菇（生） | Mushrooms, oyster, raw | 生 | 蚝菇；pg, hg |  |
| 13-505 / 1738 | 白蘑菇（生） | Mushrooms, white, raw | 生 | 双孢蘑菇；bmg, sbmg |  |
| 13-297 / 1743 | 芥菜苗与cress菜苗（生） | Mustard and cress, raw | 生，混合苗菜；cress未细分植物种 | ；jcm |  |
| 13-298 / 1745 | 芥菜叶（生） | Mustard leaves, raw | 生 | ；jcy |  |
| 13-300 / 1800 | 秋葵（生） | Okra, raw | 生 | ；qk |  |
| 13-499 / 1820 | 洋葱（生） | Onions, raw | 生 | ；yc |  |
| 13-312 / 1873 | 欧洲防风根（生） | Parsnip, raw | 生 | 欧防风；ozffg |  |
| 13-524 / 1977 | 红甜椒（生） | Pepper, capsicum, red, raw | 生 | 红彩椒；htj |  |
| 13-526 / 1979 | 黄甜椒（生） | Pepper, capsicum, yellow, raw | 生 | 黄彩椒；htj |  |
| 13-317 / 1985 | 红辣椒（生） | Peppers, capsicum, chilli, red, raw | 生 | ；hlj |  |
| 13-618 / 2224 | 新土豆（去皮，生） | Potatoes, new and salad, flesh only, raw | 生，仅薯肉 | ；xtd |  |
| 13-489 / 2235 | 土豆（成熟，去皮，生） | Potatoes, old, raw, flesh only | 生，仅薯肉 | 马铃薯；td |  |
| 13-326 / 2281 | 南瓜（仅瓜肉，生） | Pumpkin, flesh only, raw | 生，仅瓜肉 | ；ng |  |
| 13-656 / 2300 | 红皮小萝卜（带皮，生） | Radish, red, flesh and skin, raw | 生，肉及皮 | 樱桃萝卜；hpxlb |  |
| 13-331 / 2301 | 白萝卜（生） | Radish, white/mooli, raw | 生 | 大根；blb |  |
| 13-522 / 2386 | 芝麻菜（生） | Rocket, raw | 生 | 火箭菜；zmc |  |
| 13-339 / 2518 | 昆布（干） | Seaweed, kombu, dried, raw | 干品，未泡发 | 海带；kb, hd |  |
| 13-340 / 2519 | 紫菜（干） | Seaweed, nori, dried, raw | 干品，未泡发 | 海苔原料；zc |  |
| 13-341 / 2520 | 裙带菜（干） | Seaweed, wakame, dried, raw | 干品，未泡发 | ；qdc |  |
| 13-342 / 2526 | 红葱头（生） | Shallots, raw | 生 | 干葱；hct |  |
| 13-521 / 2586 | 嫩菠菜（生） | Spinach, baby, raw | 生 | ；nbc |  |
| 13-572 / 2590 | 菠菜（成熟叶，生） | Spinach, mature, raw | 生 | ；bc |  |
| 13-348 / 2596 | 春甘蓝叶（生） | Spring greens, raw | 生 | ；cgl |  |
| 13-352 / 2597 | 小葱（葱白及葱叶，生） | Spring onions, bulbs and tops, raw | 生，葱白及葱叶 | 青葱、香葱；xc, qc |  |
| 13-351 / 2598 | 小葱（仅葱白，生） | Spring onions, bulbs only, raw | 生，仅葱白 | ；xc |  |
| 13-353 / 2601 | 橡果南瓜（生） | Squash, acorn, raw | 生 | ；xgng |  |
| 13-355 / 2604 | 奶油南瓜（生） | Squash, butternut, raw | 生 | 胡桃南瓜；nyng |  |
| 13-357 / 2606 | 金丝南瓜（生） | Squash, spaghetti, raw | 生 | 意面南瓜；jsng |  |
| 13-359 / 2643 | 芜菁甘蓝（去皮，生） | Swede, flesh only, raw | 生，仅根肉 | 瑞典萝卜；wjgl |  |
| 13-463 / 2650 | 红薯（去皮，生） | Sweet potato, raw, flesh only | 生，仅薯肉 | 甘薯、番薯、地瓜；hs, gs, fs, dg |  |
| 13-622 / 2662 | 甜玉米粒（生） | Sweetcorn, kernels, raw | 生，仅籽粒 | ；tyml |  |
| 13-519 / 2726 | 圣女果（生） | Tomatoes, cherry, raw | 生 | 樱桃番茄、小番茄；sng, ytfq, xfq |  |
| 13-389 / 2797 | 芜菁（去皮，生） | Turnip, flesh only, raw | 生，仅根肉 | 蔓菁；wj |  |
| 13-397 / 2869 | 薯蓣（去皮，生） | Yam, flesh only, raw | 生，yam，仅薯肉 | ；sy |  |
| 13-514 / 144 | 四季豆（生） | Beans, green, raw | 鲜豆荚，生 | 菜豆、芸豆荚；sjd |  |
| 13-112 / 164 | 红花菜豆荚（生） | Beans, runner, raw | 鲜豆荚，生 | ；hhcdj |  |
| 13-426 / 169 | 绿豆芽（生） | Beansprouts, mung, raw | 生 | 豆芽菜；ldy, dyc |  |
| 13-438 / 1967 | 豌豆（鲜，生） | Peas, raw | 鲜豆，生 | 青豌豆；wd, qwd |  |
| 14-362 / 25 | 烹调用苹果（去皮，生） | Apples, cooking, raw, flesh only, peeled | 生，仅果肉；烹调用品种 | ；pg |  |
| 14-319 / 30 | 苹果（带皮，生） | Apples, eating, raw, flesh and skin | 生，果肉及皮 | ；pg |  |
| 14-025 / 35 | 杏（带皮，生） | Apricots, raw, flesh and skin | 生，果肉及皮，去核 | 杏子；xz |  |
| 14-039 / 63 | 牛油果（Fuerte，仅果肉） | Avocado, Fuerte, flesh only | 仅果肉 | 鳄梨；nyg, el |  |
| 14-386 / 65 | 牛油果（Hass，仅果肉） | Avocado, Hass, flesh only | 仅果肉 | 哈斯鳄梨；nyg, hsel |  |
| 14-318 / 100 | 香蕉（去皮） | Bananas, flesh only | 仅果肉 | ；xj |  |
| 14-388 / 355 | 黑莓（生） | Blackberries, raw | 生 | ；hm |  |
| 14-053 / 362 | 黑加仑（生） | Blackcurrants, raw | 生 | 黑醋栗；hjl, hcl |  |
| 14-325 / 368 | 蓝莓 | Blueberries | 未另标烹调状态 | ；lm |  |
| 14-382 / 646 | 樱桃（带皮，生） | Cherries, flesh and skin, raw | 生，果肉及皮，去核 | ；yt |  |
| 14-326 / 776 | 易剥皮柑橘（仅果肉） | Citrus fruit, soft/easy peelers, flesh only | 仅果肉，原表soft/easy peelers组 | 橘子、柑橘；ybpgj, jz, gj |  |
| 14-816 / 791 | 椰子肉（鲜） | Coconut, flesh only, fresh | 鲜果肉 | ；yzr |  |
| 14-073 / 875 | 蔓越莓 | Cranberries | 未另标烹调状态 | ；mym |  |
| 14-083 / 1035 | 椰枣（鲜，生，去核） | Dates, raw, flesh and skin | 生，果肉及皮 | ；yz |  |
| 14-091 / 1130 | 无花果（绿果，生） | Figs, whole green fruit, raw | 生，整颗绿果 | ；whg |  |
| 14-103 / 1228 | 甜味醋栗（生） | Gooseberries, dessert, raw | 生，甜食品种 | ；twcl |  |
| 14-384 / 1240 | 西柚（仅果肉，生） | Grapefruit, flesh only, raw | 生，仅果肉 | 葡萄柚；xy, pty |  |
| 14-350 / 1242 | 葡萄（平均） | Grapes, average | 平均值 | ；pt |  |
| 14-322 / 1244 | 青葡萄 | Grapes, green | 未另标烹调状态 | ；qpt |  |
| 14-323 / 1245 | 红葡萄 | Grapes, red | 未另标烹调状态 | ；hpt |  |
| 14-111 / 1249 | 青李（生） | Greengages, raw | 生 | ；ql |  |
| 14-122 / 1366 | 枣（仅果肉） | Jujube, flesh only | 仅果肉 | ；z |  |
| 14-371 / 1388 | 猕猴桃（仅果肉，生） | Kiwi fruit, flesh only, raw | 生，仅果肉 | 奇异果；mht, qyg |  |
| 14-129 / 1541 | 柠檬（去皮，仅果肉） | Lemons, peeled, flesh only | 仅果肉 | ；nm |  |
| 14-131 / 1560 | 青柠（仅果肉） | Limes, flesh only | 仅果肉 | ；qn |  |
| 14-140 / 1591 | 枇杷（仅果肉，生） | Loquats, flesh only, raw | 生，仅果肉 | ；pp |  |
| 14-142 / 1596 | 荔枝（仅果肉，生） | Lychees, raw, flesh only | 生，仅果肉 | ；lz |  |
| 14-378 / 1609 | 芒果（成熟，仅果肉，生） | Mangoes, ripe, flesh only, raw | 成熟，生，仅果肉 | ；mg |  |
| 14-339 / 1633 | 橙肉甜瓜（仅果肉） | Melon, Canteloupe-type, flesh only | 仅果肉，Canteloupe-type | 哈密瓜类；crtg |  |
| 14-354 / 1636 | 甜瓜（平均，仅果肉） | Melon, flesh only, average | 仅果肉，平均值 | ；tg |  |
| 14-159 / 1639 | 嘉丽亚甜瓜（仅果肉） | Melon, Galia, flesh only | 仅果肉，Galia品种 | Galia甜瓜；jlytg, tg |  |
| 14-296 / 1644 | 西瓜（仅瓜瓤） | Melon, watermelon, flesh only | 仅果肉 | ；xg |  |
| 14-328 / 1646 | 黄肉甜瓜（仅果肉） | Melon, yellow flesh, flesh only | 仅果肉 | ；hrtg |  |
| 14-380 / 1751 | 油桃（带皮，生） | Nectarines, flesh and skin, raw | 生，果肉及皮 | ；yt |  |
| 14-327 / 1826 | 橙（仅果肉） | Oranges, flesh only | 仅果肉 | 橙子；cz |  |
| 14-390 / 1864 | 木瓜（仅果肉，生） | Papaya, flesh only, raw | 生，仅果肉 | 番木瓜；mg, fmg |  |
| 14-178 / 1878 | 百香果（果肉及籽） | Passion fruit, flesh and pips | 果肉及籽 | 西番莲果；bxg, xflg |  |
| 14-299 / 1936 | 桃（带皮，生） | Peaches, raw, flesh and skin | 生，果肉及皮 | 桃子；tz |  |
| 14-365 / 1946 | 梨（平均，仅果肉，生） | Pears, average, raw, flesh only | 生，仅果肉，平均值 | ；l |  |
| 14-205 / 1951 | 亚洲梨（带皮，生） | Pears, Nashi, flesh and skin, raw | 生，果肉及皮，Nashi | 水梨；yzl, sl |  |
| 14-321 / 1953 | 梨（带皮，生） | Pears, raw, flesh and skin | 生，果肉及皮 | ；l |  |
| 14-207 / 1996 | 酸浆果（仅果实） | Physalis, fruit only | 仅果实 | 食用灯笼果；sjg, sydlg |  |
| 14-376 / 2048 | 菠萝（仅果肉，生） | Pineapple, flesh only, raw | 生，仅果肉 | 凤梨；bl, fl |  |
| 14-372 / 2076 | 鲜食李子（带皮，生） | Plums, dessert, flesh and skin, raw | 生，果肉及皮 | ；lz |  |
| 14-220 / 2078 | 维多利亚李子（带皮，生） | Plums, Victoria, flesh and skin, raw | 生，果肉及皮 | ；wdlylz |  |
| 14-226 / 2089 | 石榴（果肉及籽） | Pomegranate, flesh and pips | 果肉及籽 | ；sl |  |
| 14-228 / 2091 | 柚子（仅果肉） | Pomelo, flesh only | 仅果肉 | ；yz |  |
| 14-230 / 2251 | 仙人掌果（果肉及籽） | Prickly pears, flesh and seeds | 果肉及籽 | ；xrzg |  |
| 14-375 / 2307 | 覆盆子（生） | Raspberries, raw | 生 | 树莓；fpz, sm |  |
| 14-252 / 2325 | 大黄（仅茎，生） | Rhubarb, stems only, raw | 生，仅茎 | ；dh |  |
| 14-259 / 2530 | 沙龙柿（仅果肉） | Sharon fruit, flesh only | 仅果肉 | Sharon柿；sls |  |
| 14-059 / 2609 | 杨桃 | Star fruit | 未另标烹调状态 | ；yt |  |
| 14-324 / 2624 | 草莓（生） | Strawberries, raw | 生 | ；cm |  |
| 14-264 / 2674 | 树番茄（果肉及籽） | Tamarillos, flesh and seeds | 果肉及籽 | ；sfq |  |
| 14-268 / 2844 | 白醋栗（生） | Whitecurrants, raw | 生 | ；bcl |  |
| 13-887 / 747 | 细香葱（鲜） | Chives, fresh | 鲜 | 西式香葱；xxc, xsxc |  |
| 13-890 / 1219 | 姜（鲜） | Ginger, fresh | 鲜 | 生姜；j, sj |  |
| 13-893 / 2709 | 百里香（鲜） | Thyme, fresh | 鲜 | ；blx |  |

### protein_main

| 编码／行 | 简体名 | 英文原名 | 状态 | 别名；首字母 | 旧 |
| --- | --- | --- | --- | --- | --- |
| 12-937 / 1096 | 鸡蛋（全蛋，生） | Eggs, chicken, whole, raw | 生，全蛋 | 全蛋；jd, qd | 旧 |
| 13-570 / 2719 | 豆腐（原味/蒸） | Tofu, soya bean, steamed | 蒸制 | 蒸豆腐；df | 旧 |
| 18-006 / 180 | 炖煮牛肉（生瘦肉） | Beef, braising steak, raw, lean | 生，炖煮用瘦肉 | 炖煮用生牛瘦肉；dznr | 旧 |
| 18-020 / 195 | 牛排（烤熟瘦肉） | Beef, fillet steak, grilled, lean | 烤熟，fillet steak，仅瘦肉 | ；np | 旧 |
| 18-323 / 677 | 鸡胸肉（去皮烤熟） | Chicken, breast, grilled without skin, meat only | 烤熟，去皮，仅肉 | 熟鸡胸肉；jxr | 旧 |
| 18-319 / 717 | 鸡腿肉（去皮炖熟） | Chicken, thighs, casseroled, meat only, diced | 炖熟，去皮，仅肉 | ；jtr | 旧 |
| 13-062 / 128 | 眉豆（整粒干豆，生） | Beans, blackeye, whole, dried, raw | 干豆，未煮 | 黑眼豆；md, hyd |  |
| 13-067 / 129 | 蚕豆（干，生） | Beans, broad, dried, raw | 干豆，未煮 | ；cd |  |
| 13-064 / 131 | 蚕豆（鲜整粒，生） | Beans, broad, whole, raw | 鲜豆，生 | ；cd |  |
| 13-070 / 134 | 利马豆（干，生） | Beans, butter, dried, raw | 干豆，未煮 | 奶油豆；lmd, nyd |  |
| 13-076 / 138 | 鹰嘴豆（Kabuli，干分瓣，生） | Beans, chick peas, Kabuli, split, dried, raw | 干豆，分瓣，未煮 | ；yzd |  |
| 13-074 / 140 | 鹰嘴豆（Kabuli，干整粒，生） | Beans, chick peas, Kabuli, whole, dried, raw | 干豆，整粒，未煮 | ；yzd |  |
| 13-086 / 147 | 白芸豆（干整粒，生） | Beans, haricot, whole, dried, raw | 干豆，未煮 | ；byd |  |
| 13-098 / 149 | 去皮绿豆瓣（干，生） | Beans, mung, dahl, dried, raw | 干豆瓣，未煮 | ；qpldb |  |
| 13-096 / 151 | 绿豆（干整粒，生） | Beans, mung, whole, dried, raw | 干豆，未煮 | ；ld |  |
| 13-104 / 154 | 木豆瓣（干，生） | Beans, pigeon peas, dahl, dried, raw | 干豆瓣，未煮 | ；mdb |  |
| 13-102 / 156 | 木豆（干整粒，生） | Beans, pigeon peas, whole, dried, raw | 干豆，未煮 | ；md |  |
| 13-109 / 162 | 红腰豆（干，生） | Beans, red kidney, dried, raw | 干豆，未煮 | 红芸豆；hyd |  |
| 13-115 / 166 | 黄豆（干，生） | Beans, soya, dried, raw | 干豆，未煮 | 大豆；hd, dd |  |
| 13-056 / 352 | 黑绿豆（整粒干豆，生） | Black gram, urad gram, whole, dried, raw | 干豆，未煮 | 乌拉德豆；hld, wldd |  |
| 13-089 / 1553 | 绿扁豆与棕扁豆（干整粒，生） | Lentils, green and brown, whole, dried, raw | 干豆，未煮 | ；lbd |  |
| 13-657 / 1555 | 红扁豆（干分瓣，生） | Lentils, red, split, dried, raw | 干豆瓣，未煮 | ；hbd |  |
| 13-130 / 1958 | 豌豆（干，生） | Peas, dried, raw | 干豆，未煮 | ；wd |  |
| 13-141 / 1969 | 豌豆瓣（干，生） | Peas, split, dried, raw | 干豆瓣，未煮 | ；wdb |  |
| 13-063 / 127 | 眉豆（干豆无盐煮熟） | Beans, blackeye, whole, dried, boiled in unsalted water | 干豆煮熟，无盐 | 黑眼豆（熟）；md |  |
| 13-663 / 133 | 利马豆（干豆无盐煮熟） | Beans, butter, dried, boiled in unsalted water | 干豆煮熟，无盐 | 奶油豆（熟）；lmd |  |
| 13-662 / 139 | 鹰嘴豆（Kabuli，干整粒无盐煮熟） | Beans, chick peas, Kabuli, whole, dried, boiled in unsalted water | 干豆煮熟，无盐 | ；yzd |  |
| 13-664 / 150 | 绿豆（干整粒无盐煮熟） | Beans, mung, whole, dried, boiled in unsalted water | 干豆煮熟，无盐 | ；ld |  |
| 13-659 / 161 | 红腰豆（干豆无盐煮熟） | Beans, red kidney, dried, boiled in unsalted water | 干豆煮熟，无盐 | ；hyd |  |
| 13-116 / 165 | 黄豆（干豆无盐煮熟） | Beans, soya, dried, boiled in unsalted water | 干豆煮熟，无盐 | ；hd |  |
| 13-661 / 1552 | 绿扁豆与棕扁豆（干豆无盐煮熟） | Lentils, green and brown, whole, dried, boiled in unsalted water | 干豆煮熟，无盐 | ；lbd |  |
| 13-658 / 1554 | 红扁豆（干分瓣无盐煮熟） | Lentils, red, split, dried, boiled in unsalted water | 干豆煮熟，无盐 | ；hbd |  |
| 18-007 / 181 | 炖煮牛肉（生，瘦肉及脂肪） | Beef, braising steak, raw, lean and fat | 生，braising steak，瘦肉及脂肪 | ；dznr |  |
| 18-012 / 186 | 牛胸肉（生，瘦肉） | Beef, brisket, raw, lean | 生，brisket，仅瘦肉 | ；nxr |  |
| 18-013 / 187 | 牛胸肉（生，瘦肉及脂肪） | Beef, brisket, raw, lean and fat | 生，brisket，瘦肉及脂肪 | ；nxr |  |
| 18-016 / 197 | 牛里脊（生，瘦肉） | Beef, fillet steak, raw, lean | 生，fillet，仅瘦肉 | 菲力牛排；nlj, flnp |  |
| 18-024 / 201 | 牛腹胁肉（生，瘦肉） | Beef, flank, raw, lean | 生，flank，仅瘦肉 | ；nfxr |  |
| 18-468 / 211 | 牛瘦肉（平均，生） | Beef, lean, average, raw | 生，仅瘦肉，平均值 | ；nsr |  |
| 18-469 / 217 | 牛肉糜（生） | Beef, mince, raw | 生，原表普通肉糜 | 牛肉末；nrm |  |
| 18-508 / 218 | 牛肉糜（特瘦，生） | Beef, mince, raw, extra lean | 生，extra lean | ；nrm |  |
| 18-043 / 230 | 牛臀肉牛排（生，瘦肉） | Beef, rump steak, raw, lean | 生，rump，仅瘦肉 | ；ntrnp |  |
| 18-054 / 236 | 牛后腿外侧肉（生，瘦肉） | Beef, silverside, raw, lean | 生，silverside，仅瘦肉 | ；nhtwcr |  |
| 18-064 / 254 | 西冷牛排（生，瘦肉） | Beef, sirloin steak, raw, lean | 生，sirloin，仅瘦肉 | 沙朗牛排；xlnp, slnp |  |
| 18-076 / 260 | 慢炖牛肉（生，瘦肉） | Beef, stewing steak, raw, lean | 生，stewing steak，仅瘦肉 | ；mdnr |  |
| 18-084 / 267 | 牛后腿内侧肉（生，瘦肉） | Beef, topside, raw, lean | 生，topside，仅瘦肉 | ；nhtncr |  |
| 18-289 / 687 | 鸡深色肉（生） | Chicken, dark meat, raw | 生，dark meat | ；jssr |  |
| 18-290 / 702 | 鸡浅色肉（生） | Chicken, light meat, raw | 生，light meat；不把整项强称鸡胸 | 鸡白肉；jqsr, jbr |  |
| 18-488 / 704 | 鸡肉（平均，生） | Chicken, meat, average, raw | 生，平均肉 | ；jr |  |
| 18-293 / 698 | 鸡腿四分体肉及皮（生） | Chicken, leg quarter, raw, meat and skin | 生，leg quarter，仅可食肉及皮，不计骨重 | ；jtsft |  |
| 18-295 / 729 | 鸡翅四分体肉及皮（生） | Chicken, wing quarter, raw, meat and skin | 生，wing quarter，仅可食肉及皮，不计骨重 | ；jcsft |  |
| 18-297 / 722 | 全鸡（生，肉及皮） | Chicken, whole, raw, meat and skin | 生，肉及皮 | ；qj |  |
| 18-489 / 1072 | 鸭肉（生，去皮） | Duck, meat only, raw | 生，仅肉 | ；yr |  |
| 18-371 / 1074 | 鸭（生，肉、脂肪及皮） | Duck, raw, meat, fat and skin | 生，肉、脂肪及皮 | ；y |  |
| 18-375 / 1223 | 鹅（生，肉、脂肪及皮） | Goose, meat, raw, fat and skin | 生，肉、脂肪及皮 | ；e |  |
| 18-475 / 1429 | 羊瘦肉（平均，生） | Lamb, lean only, raw, average | 生，仅瘦肉，平均值 | ；ysr |  |
| 18-478 / 1403 | 羊肉（平均，生，瘦肉及脂肪） | Lamb, average, raw, lean and fat | 生，瘦肉及脂肪，平均值 | ；yr |  |
| 18-481 / 1465 | 羊肉糜（生） | Lamb, mince, raw | 生 | 羊肉末；yrm |  |
| 18-160 / 1468 | 羊颈肉（生，瘦肉） | Lamb, neck fillet, raw, lean | 生，neck fillet，仅瘦肉 | ；yjr |  |
| 18-170 / 1498 | 羊肩肉（生，瘦肉及脂肪） | Lamb, shoulder, raw, lean and fat | 生，shoulder，瘦肉及脂肪 | ；yjr |  |
| 18-182 / 1505 | 炖煮羊肉（生，瘦肉及脂肪） | Lamb, stewing, raw, lean and fat | 生，stewing，瘦肉及脂肪 | ；dzyr |  |
| 18-348 / 2771 | 火鸡深色肉（生） | Turkey, dark meat, raw | 生，dark meat | ；hjssr |  |
| 18-349 / 2776 | 火鸡浅色肉（生） | Turkey, light meat, raw | 生，light meat | ；hjqsr |  |
| 18-350 / 2778 | 火鸡肉（平均，生） | Turkey, meat, average, raw | 生，平均肉 | ；hjr |  |
| 18-387 / 2295 | 兔肉（生） | Rabbit, raw, meat only | 生，仅肉 | ；tr |  |
| 18-390 / 2816 | 鹿肉（生） | Venison, meat only, raw | 生，仅肉 | ；lr |  |
| 16-385 / 116 | 海鲈鱼肉（生） | Bass, sea, flesh only, raw | 生，仅鱼肉 | ；hlyr |  |
| 16-172 / 537 | 鲤鱼（生） | Carp, raw | 生 | ；ly |  |
| 16-007 / 564 | 鲶鱼（生） | Catfish, raw | 生 | ；ny |  |
| 16-372 / 799 | 鳕鱼肉（生） | Cod, flesh only, raw | 生，cod，仅鱼肉 | ；xyr |  |
| 16-383 / 831 | 绿青鳕鱼肉（生） | Coley, flesh only, raw | 生，coley，仅鱼肉 | ；lqxyr |  |
| 16-040 / 1161 | 川鲽（生） | Flounder, raw | 生 | flounder；cd |  |
| 16-375 / 1275 | 黑线鳕鱼肉（生） | Haddock, flesh only, raw | 生，haddock，仅鱼肉 | ；hxxyr |  |
| 16-070 / 1290 | 无须鳕鱼肉（生） | Hake, flesh only, raw | 生，hake，仅鱼肉 | ；wxxyr |  |
| 16-073 / 1294 | 大比目鱼肉（生） | Halibut, flesh only, raw | 生，halibut，仅鱼肉 | ；dbmyr |  |
| 16-175 / 1314 | 鲱鱼肉（生） | Herring, flesh only, raw | 生，仅鱼肉 | ；fyr |  |
| 16-078 / 1321 | 蓝尖尾无须鳕（生） | Hoki, raw | 生，hoki | ；ljwwxx |  |
| 16-080 / 1365 | 海鲂（生） | John Dory, raw | 生 | John Dory；hf |  |
| 16-393 / 1603 | 鲭鱼肉（生） | Mackerel, flesh only, raw | 生，仅鱼肉 | ；qyr |  |
| 16-092 / 1701 | 鮟鱇鱼肉（生） | Monkfish, flesh only, raw | 生，仅鱼肉 | ；akyr |  |
| 16-095 / 1721 | 鲻鱼肉（生） | Mullet, Grey, flesh only, raw | 生，grey mullet，仅鱼肉 | ；zyr |  |
| 16-497 / 1742 | 贻贝（生） | Mussels, raw | 生 | 淡菜、青口贝；yb, dc, qkb |  |
| 16-260 / 1838 | 牡蛎（生） | Oysters, raw | 生 | 生蚝；ml, sh |  |
| 16-382 / 1862 | 芒鱼属鲶鱼肉（Pangasius，生） | Pangasius, flesh only, raw | 生，Pangasius，仅鱼肉 | Pangasius鱼肉；nyr |  |
| 16-381 / 2062 | 欧洲鲽鱼肉（生） | Plaice, flesh only, raw | 生，plaice，仅鱼肉 | ；ozdyr |  |
| 16-378 / 2086 | 阿拉斯加狭鳕鱼肉（生） | Pollock, Alaskan, flesh only, raw | 生，仅鱼肉 | ；alsjxxyr |  |
| 16-124 / 2093 | 黑鲳（生） | Pomfret, black, raw | 生 | ；hc |  |
| 16-125 / 2094 | 白鲳（生） | Pomfret, white, raw | 生 | ；bc |  |
| 16-387 / 2247 | 大虾（生） | Prawns, king, raw | 生，king prawns | 对虾；dx |  |
| 16-384 / 2249 | 普通虾（购入时已熟） | Prawns, standard, purchased cooked | 购入熟制，原表standard prawns | ；ptx |  |
| 16-356 / 2422 | 养殖三文鱼肉（生） | Salmon, farmed, flesh only, raw | 生，仅鱼肉 | ；yzswyr |  |
| 16-360 / 2431 | 野生三文鱼肉（生） | Salmon, wild, flesh only, raw | 生，仅鱼肉 | ；ysswyr |  |
| 16-401 / 2455 | 沙丁鱼肉（生） | Sardines, flesh only, raw | 生，仅鱼肉 | ；sdyr |  |
| 16-263 / 2608 | 鱿鱼（生） | Squid, raw | 生 | ；yy |  |
| 16-254 / 1023 | 墨鱼（生） | Cuttlefish, raw | 生 | 乌贼；my, wz |  |
| 16-395 / 2758 | 虹鳟鱼肉（生） | Trout, rainbow, flesh only, raw | 生，仅鱼肉 | ；hzyr |  |
| 16-399 / 2764 | 金枪鱼肉（生） | Tuna, flesh only, raw | 生，仅鱼肉 | 吞拿鱼；jqyr, tny |  |
| 16-154 / 2711 | 罗非鱼（生） | Tilapia, raw | 生 | ；lfy |  |
| 16-155 / 2767 | 多宝鱼肉（生） | Turbot, flesh only, raw | 生，仅鱼肉 | 大菱鲆；dbyr, dlp |  |
| 16-159 / 2847 | 牙鳕鱼肉（生） | Whiting, flesh only, raw | 生，whiting，仅鱼肉 | ；yxyr |  |
| 12-938 / 1090 | 鸡蛋白（生） | Eggs, chicken, white, raw | 生 | 蛋清；jdb, dq |  |
| 12-939 / 1099 | 鸡蛋黄（生） | Eggs, chicken, yolk, raw | 生 | 蛋黄；jdh, dh |  |
| 12-940 / 1091 | 鸡蛋（全蛋，水煮） | Eggs, chicken, whole, boiled | 水煮，全蛋 | ；jd |  |
| 12-941 / 1088 | 鸡蛋白（水煮） | Eggs, chicken, white, boiled | 水煮，仅蛋白 | ；jdb |  |
| 12-942 / 1098 | 鸡蛋黄（水煮） | Eggs, chicken, yolk, boiled | 水煮，仅蛋黄 | ；jdh |  |
| 12-943 / 1095 | 鸡蛋（全蛋，水波蛋） | Eggs, chicken, whole, poached | 水中汆熟，全蛋 | ；jd |  |
| 12-962 / 1094 | 鸡蛋（全蛋，无油煎） | Eggs, chicken, whole, fried, without fat | 煎制，无外加脂肪 | ；jd |  |
| 12-963 / 1097 | 鸡蛋（全蛋，炒制，不加奶） | Eggs, chicken, whole, scrambled, without milk | 炒制，不加奶 | ；jd |  |
| 12-920 / 1101 | 鸭蛋（全蛋，生） | Eggs, duck, whole, raw | 生，全蛋 | ；yd |  |

### oil

| 编码／行 | 简体名 | 英文原名 | 状态 | 别名；首字母 | 旧 |
| --- | --- | --- | --- | --- | --- |
| 17-041 / 1789 | 菜籽油 | Oil, rapeseed | 油脂 | ；czy | 旧 |
| 17-033 / 1781 | 玉米油 | Oil, corn | 油脂 | ；ymy |  |
| 17-036 / 1784 | 葡萄籽油 | Oil, grapeseed | 油脂 | ；ptzy |  |
| 17-037 / 1785 | 榛子油 | Oil, hazelnut | 油脂 | ；zzy |  |
| 17-038 / 1786 | 橄榄油 | Oil, olive | 油脂 | ；gly |  |
| 17-039 / 1787 | 棕榈油 | Oil, palm | 油脂 | ；zly |  |
| 17-040 / 1788 | 花生油 | Oil, peanut (groundnut) | 油脂 | ；hsy |  |
| 17-042 / 1790 | 红花籽油 | Oil, safflower | 油脂 | ；hhzy |  |
| 17-043 / 1791 | 芝麻油 | Oil, sesame | 油脂 | 香油；zmy, xy |  |
| 17-044 / 1792 | 大豆油 | Oil, soya | 油脂 | ；ddy |  |
| 17-045 / 1793 | 葵花籽油 | Oil, sunflower | 油脂 | ；khzy |  |
| 17-686 / 1794 | 植物油（平均） | Oil, vegetable, average | 油脂，平均值 | ；zwy |  |
| 17-047 / 1795 | 核桃油 | Oil, walnut | 油脂 | ；hty |  |
| 17-048 / 1796 | 小麦胚芽油 | Oil, wheatgerm | 油脂 | ；xmpyy |  |

### sauce

| 编码／行 | 简体名 | 英文原名 | 状态 | 别名；首字母 | 旧 |
| --- | --- | --- | --- | --- | --- |
| 17-721 / 2581 | 酱油（生抽/老抽平均） | Soy sauce, light and dark varieties | 生抽及老抽合并值，按质量计 | 生抽、老抽；jy | 旧 |
| 14-892 / 1938 | 花生酱（顺滑型） | Peanut butter, smooth | 原表顺滑型 | ；hsj |  |
| 14-847 / 2673 | 芝麻酱 | Tahini paste | 研磨酱 | ；zmj |  |
| 13-830 / 1207 | 大蒜粉 | Garlic powder | 干粉 | ；dsf |  |
| 13-832 / 1220 | 姜粉 | Ginger, ground | 干粉 | ；jf |  |
| 13-883 / 2708 | 百里香（干，研磨） | Thyme, dried, ground | 干香草，研磨 | ；blx |  |
| 17-367 / 2436 | 食盐 | Salt | 盐，按质量计 | ；sy |  |
| 17-355 / 97 | 泡打粉 | Baking powder | 膨松剂，干粉 | ；pdf |  |
| 17-356 / 323 | 小苏打 | Bicarbonate of soda | 膨松剂，干粉 | 碳酸氢钠；xsd, tsqn |  |
| 17-358 / 879 | 塔塔粉 | Cream of tartar | 膨松剂，干粉 | 酒石酸氢钾；ttf, jssqj |  |

### snack_dessert

| 编码／行 | 简体名 | 英文原名 | 状态 | 别名；首字母 | 旧 |
| --- | --- | --- | --- | --- | --- |
| 14-016 / 29 | 苹果干 | Apples, eating, dried | 干果 | ；pgg |  |
| 14-392 / 37 | 杏干（半干，即食） | Apricots, ready-to-eat, semi-dried | 半干果，即食 | ；xg |  |
| 14-873 / 790 | 椰蓉（干） | Coconut, desiccated | 干品 | ；yr |  |
| 14-394 / 1033 | 椰枣（干，去核） | Dates, dried, flesh and skin | 干果，果肉及皮 | ；yz |  |
| 14-395 / 1128 | 无花果干（半干，即食） | Figs, ready-to-eat, semi-dried | 半干果，即食 | ；whgg |  |
| 14-874 / 1304 | 榛子仁 | Hazelnuts, kernel only | 仅果仁 | ；zzr |  |
| 14-137 / 1590 | 桂圆（干，仅果肉） | Longans, flesh only, dried | 干果，仅果肉 | 龙眼干；gy, lyg |  |
| 14-396 / 2047 | 菠萝干 | Pineapple, dried | 干果 | ；blg |  |
| 14-391 / 2261 | 西梅干（半干，即食） | Prunes, ready-to-eat, semi-dried | 半干果，即食 | ；xmg |  |
| 14-393 / 2302 | 葡萄干 | Raisins, dried | 干果 | ；ptg |  |
| 14-896 / 12 | 巴旦木仁（整粒） | Almonds, whole kernels | 仅果仁 | 扁桃仁；bdmr, btr |  |
| 14-870 / 9 | 巴旦木片与粉 | Almonds, flaked and ground | 切片及研磨，合并值 | ；bdm |  |
| 14-897 / 10 | 巴旦木仁（烘烤） | Almonds, toasted | 烘烤 | ；bdmr |  |
| 14-871 / 380 | 巴西坚果仁 | Brazil nuts, kernel only | 仅果仁 | ；bxjgr |  |
| 14-811 / 546 | 腰果仁（原味） | Cashew nuts, kernel only, plain | 仅果仁，原味 | ；ygr |  |
| 14-813 / 656 | 栗子仁（生） | Chestnuts, kernel only, raw | 生，仅果仁 | ；lzr |  |
| 14-815 / 655 | 栗子（干） | Chestnuts, dried | 干品 | ；lz |  |
| 14-877 / 1941 | 花生仁（原味，无盐） | Peanuts, kernel only, plain, unsalted | 仅果仁，未加盐 | ；hsr |  |
| 14-878 / 1940 | 花生仁（干烤） | Peanuts, dry roasted | 干烤 | ；hsr |  |
| 14-837 / 1972 | 碧根果仁 | Pecan nuts, kernel only | 仅果仁 | ；bggr |  |
| 14-839 / 2043 | 松子仁 | Pine nuts, kernel only | 仅果仁 | ；szr |  |
| 14-840 / 2051 | 开心果仁（烘烤，加盐） | Pistachio nuts, kernel only, roasted and salted | 烘烤，加盐 | ；kxgr |  |
| 14-842 / 2279 | 南瓜子 | Pumpkin seeds | 未另标烹调状态 | ；ngz |  |
| 14-844 / 2523 | 芝麻 | Sesame seeds | 未另标烹调状态 | ；zm |  |
| 14-845 / 2637 | 葵花籽 | Sunflower seeds | 未另标烹调状态 | ；khz |  |
| 14-846 / 2638 | 葵花籽（烘烤） | Sunflower seeds, toasted | 烘烤 | ；khz |  |
| 14-879 / 2823 | 核桃仁 | Walnuts, kernel only | 仅果仁 | ；htr |  |
| 12-555 / 2875 | 希腊式酸奶（原味） | Yogurt, Greek style, plain | 发酵乳，原味 | ；xlssn |  |
| 12-379 / 2878 | 低脂酸奶（原味） | Yogurt, low fat, plain | 发酵乳，原味 | ；dzsn |  |
| 12-533 / 2882 | 近乎无脂酸奶（原味） | Yogurt, virtually fat free/diet, plain | 发酵乳，原味 | ；jhwzsn |  |
| 12-184 / 2885 | 全脂酸奶（原味） | Yogurt, whole milk, plain | 发酵乳，原味 | ；qzsn |  |

### beverage

| 编码／行 | 简体名 | 英文原名 | 状态 | 别名；首字母 | 旧 |
| --- | --- | --- | --- | --- | --- |
| 12-512 / 1656 | 牛奶（1%脂肪，巴氏杀菌） | Milk, 1% fat, pasteurised | 巴氏杀菌，按质量计 | ；nn |  |
| 12-313 / 1669 | 半脱脂牛奶（巴氏杀菌，平均） | Milk, semi-skimmed, pasteurised, average | 巴氏杀菌，平均值，按质量计 | ；btznn |  |
| 12-314 / 1672 | 半脱脂牛奶（UHT） | Milk, semi-skimmed, UHT | UHT，按质量计 | ；btznn |  |
| 12-307 / 1675 | 脱脂牛奶（巴氏杀菌，平均） | Milk, skimmed, pasteurised, average | 巴氏杀菌，平均值，按质量计 | ；tznn |  |
| 12-596 / 1681 | 全脂牛奶（巴氏杀菌，平均） | Milk, whole, pasteurised, average | 巴氏杀菌，平均值，按质量计 | ；qznn |  |
| 12-320 / 1684 | 全脂牛奶（UHT） | Milk, whole, UHT | UHT，按质量计 | ；qznn |  |
| 12-328 / 1665 | 山羊奶（巴氏杀菌） | Milk, goats, pasteurised | 巴氏杀菌，按质量计 | ；syn |  |
| 12-329 / 1673 | 绵羊奶（生） | Milk, sheeps, raw | 生乳，按质量计 | ；myn |  |
| 12-520 / 1660 | 全脂甜炼乳 | Milk, condensed, whole, sweetened | 浓缩，加糖，按质量计 | ；qztlr |  |
| 12-522 / 1662 | 全脂淡奶 | Milk, evaporated, whole | 蒸发浓缩，按质量计 | ；qzdn |  |
| 12-324 / 1661 | 低脂淡奶 | Milk, evaporated, light | 蒸发浓缩，按质量计 | ；dzdn |  |
| 12-521 / 1674 | 强化脱脂奶粉 | Milk, skimmed, dried, fortified | 干奶粉，未冲调，按质量计 | ；qhtznf |  |
| 12-524 / 1680 | 未加糖强化豆奶 | Milk, soya, non-dairy alternative to milk, unsweetened, fortified | 未加糖，强化型，按质量计 | ；wjtqhdn |  |
| 12-523 / 1679 | 加糖强化豆奶 | Milk, soya, non-dairy alternative to milk, sweetened, fortified | 加糖，强化型，按质量计 | ；jtqhdn |  |
