# OPT-12 补充来源小样本记录

日期：2026-10-18。仅公开来源抽样，**这些数据均未加入正式目录，也未写入用户数据库**。正式 357 项仍全部来自 GOV.UK CoFID 2021 原始 Excel。未注册、申请 key、联系机构、接受条款或批量抓取第二个数据库。

## SG FoodID：实际取得的 3 个详情

通过新加坡 HPB 官方[Food Search](https://pphtpc.hpb.gov.sg/web/sgfoodid/tools/food-search)正常界面检索 `rice`、`white rice`、`egg fried rice` 并打开对应详情。静态抓取只能看到 React 外壳，浏览器实际界面可读。没有把页面搜索结果数量当全库规模。

| 样本 | 官方编码／详情 | 来源与逐项年份 | 食品状态／份量 |
| --- | --- | --- | --- |
| 原料：Rice flour | [F05040011](https://pphtpc.hpb.gov.sg/web/sgfoodid/tools/food-search/details/F05040011) | Borrowed；Last Updated **2025** | 米粉原料，细白粉末；可食部100%；1 cup=158g |
| 熟主食：Cooked white rice | [F05090006](https://pphtpc.hpb.gov.sg/web/sgfoodid/tools/food-search/details/F05090006) | Borrowed；Last Updated **2025** | 蒸白米饭；可食部100%；1 bowl=200g |
| 混合熟食：Egg fried rice | [F05100049](https://pphtpc.hpb.gov.sg/web/sgfoodid/tools/food-search/details/F05100049) | Lab Analysis；Last Updated **2023** | 鸡蛋、葱及调味料炒饭；可食部100%；1 plate=303g |

抽样数据署名：Health Promotion Board, Singapore Food Insights Database (SG FoodID), accessed 18 October 2026. Data are provided as-is; no HPB endorsement is implied. 本报告只含少量公共事实对照及出处，不包含网站图片、标志或整库副本。

下表为界面报告的 **Per 100g edible portion**，只抄录用于字段可用性核对，不做 CoFID 换算或补值。

| 样本 | kcal | 蛋白g | 总脂肪g | 饱和g | 碳水g | 糖g | Dietary Fibre g | 钠mg | 反式g |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Rice flour | 366 | 5.95 | 1.42 | 0.39 | 80.13 | 0.12 | 2.4 | 0 | `-` |
| Cooked white rice | 130 | 2.69 | 0.28 | 0 | 28.2 | 0.05 | 0.4 | 1 | `-` |
| Egg fried rice | 217 | 6.95 | 8.71 | 3.66 | 27.64 | 0 | 0.51 | 323 | `-` |

这三个详情都明确说明：`Trace` 是低于可靠测量／检出能力的痕量，`-` 是无数据，Per 100g 以可食部计；按份量的列则按含不可食部的整份重量计算，可食比例低于100%时不能直接混用。本次只记录三项可食比例均为100%的样本，不把其他食品默认为100%。

详情只写 Dietary Fibre，未显示足以确认 AOAC／NSP 的分析方法，不能直接映射成 CoFID AOAC。Borrowed 页面未显示具体借入原库／逐项权利链；不能把它们称为新加坡本地实测。三项页面页脚均为网站 Last Updated 26 Mar 2026，与各食品的2025／2023年份分开。

沿用前轮已核的 [SG FoodID 专用条款](https://file.go.gov.sg/termsofuse-hpbsgfoodid.pdf)与[About Our Data](https://pphtpc.hpb.gov.sg/web/sgfoodid/about-our-data)区分数据许可、网站素材和第三方权利；2026-10-18 web 文本工具未成功重取条款 PDF，本轮未点击同意。正式接入前仍需冻结当时条款、确认 Borrowed 的具体来源与权利、纤维／碳水／能量定义和可复现下载。本次未导出整库，结论为**值得后续核实，尚未纳入**。

## TFDA：实际访问结果与未取得的样本

[政府开放数据集8543](https://data.gov.tw/dataset/8543)正常可读，字段含整合编号、样品名／俗名／英文名、内容描述、废弃率、分析项及单位、每100克含量、样本数／标准差和每单位重量。页面显示免费、政府资料开放授权条款第1版、每3月更新，詮釋資料更新時間为 **2026-10-05 08:34**；此时间不证明整库营养分析或发布版本是2026。

[官方查询站](https://consumer.fda.gov.tw/Food/TFND.aspx?nodeID=178)实际访问遇到以下问题：web读取超时；Python HTTPS读取出现connection reset；Chrome导航返回 `ERR_CONNECTION_CLOSED`。未绕过安全限制或访问用户数据。原有 infoId20 页面已重定向至 [Swagger UI](https://data.fda.gov.tw/swagger-ui/index.html)。

从该站公开加载的 [Swagger 配置](https://data.fda.gov.tw/data/v3/api-docs/swagger-config)与[食品类 OpenAPI 文档](https://data.fda.gov.tw/data/dataset/oas/classification/8d4ca1bf-ae1d-4280-849e-2fa2947a9cb2)确认：数据集20确有 `/opendata/export/20/csv`、`json`、`xml` 整库导出定义，server为 `https://data.fda.gov.tw/data`；此定义未发布分页或食品筛选参数。未把其他数据集的分页方式猜到本接口，也未为了小样本抓取整库。

| 拟抽样类别 | 拟核对食品 | 本次实际结果 |
| --- | --- | --- |
| 原料 | 白米／鸡胸肉 | 查询站连接失败，未取得原编码、值或分析年 |
| 熟主食 | 白饭 | 同上；不能拿熟饭网页摘要冒充原始记录 |
| 混合熟菜 | 蛋炒饭／常见中式熟菜 | 同上；未验证其是否存在于当前库 |

因此“2016／2,076／94、2020下载文件”等历史数字本轮仍未通过当前原始文件独立核实；不能改写为已核事实。TFDA 本轮结论是**官方元数据／下载路径确认，食品级抽样受访问条件限制、未完成、未纳入**。这是来源访问限制，不是 App 或导入器代码失败，也不是证明 TFDA 数据不可用。

## 后续接入门槛

任何来源正式加入目录前，需重新提交具体原文件或食品记录、版本／逐项时间、许可与权利例外、原编码、基准、生熟／配料和必需字段完整性。TFDA 长表按编号关联，不按中文名覆盖；SG 的 Borrowed／Derived／Lab Analysis／NIP 分别保留。未确认的纤维、缺失值、份量或未知配方不得从 CoFID 复制填补。
