from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


OUTPUT_DIR = Path("deliverables")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_PATH = OUTPUT_DIR / "个人食品决策助手第一阶段项目落实计划书.docx"

# Arial Unicode MS is present on macOS and has complete Simplified Chinese
# coverage in both Word and the bundled LibreOffice renderer used for QA.
FONT_BODY = "Arial Unicode MS"
FONT_HEAD = "Arial Unicode MS"
COLOR_NAVY = "17365D"
COLOR_BLUE = "DCE6F1"
COLOR_BLUE_PALE = "F3F7FB"
COLOR_GRAY = "F2F2F2"
COLOR_BORDER = "D9D9D9"
COLOR_TEXT_GRAY = "666666"


def set_run_font(run, name=FONT_BODY, size=None, bold=None, color=None):
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), "Arial")
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), "Arial")
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color is not None:
        run.font.color.rgb = RGBColor.from_string(color)


def set_cell_shading(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=100, start=110, bottom=100, end=110):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for margin, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{margin}"))
        if node is None:
            node = OxmlElement(f"w:{margin}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_table_borders(table, color=COLOR_BORDER, size="6"):
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.find(qn("w:tblBorders"))
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        tag = borders.find(qn(f"w:{edge}"))
        if tag is None:
            tag = OxmlElement(f"w:{edge}")
            borders.append(tag)
        tag.set(qn("w:val"), "single")
        tag.set(qn("w:sz"), size)
        tag.set(qn("w:space"), "0")
        tag.set(qn("w:color"), color)


def set_repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)


def set_row_cant_split(row):
    """Keep a logical table row on one page when it fits."""
    tr_pr = row._tr.get_or_add_trPr()
    cant_split = OxmlElement("w:cantSplit")
    cant_split.set(qn("w:val"), "true")
    tr_pr.append(cant_split)


def set_cell_width(cell, inches):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_w = tc_pr.find(qn("w:tcW"))
    if tc_w is None:
        tc_w = OxmlElement("w:tcW")
        tc_pr.append(tc_w)
    tc_w.set(qn("w:w"), str(int(inches * 1440)))
    tc_w.set(qn("w:type"), "dxa")


def format_cell(cell, header=False, center=False, font_size=9.3):
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_margins(cell)
    for paragraph in cell.paragraphs:
        paragraph.paragraph_format.space_before = Pt(0)
        paragraph.paragraph_format.space_after = Pt(0)
        paragraph.paragraph_format.line_spacing = 1.08
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER if center else WD_ALIGN_PARAGRAPH.LEFT
        for run in paragraph.runs:
            set_run_font(
                run,
                name=FONT_HEAD if header else FONT_BODY,
                size=font_size,
                bold=header,
                color="FFFFFF" if header else "000000",
            )


def add_table(doc, headers, rows, widths=None, center_cols=None, font_size=9.3):
    center_cols = set(center_cols or [])
    table = doc.add_table(rows=1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_borders(table)
    header_row = table.rows[0]
    set_repeat_table_header(header_row)
    set_row_cant_split(header_row)
    for idx, text in enumerate(headers):
        cell = header_row.cells[idx]
        cell.text = str(text)
        set_cell_shading(cell, COLOR_NAVY)
        if widths:
            set_cell_width(cell, widths[idx])
        format_cell(cell, header=True, center=True, font_size=9.2)
    for row_idx, values in enumerate(rows):
        row = table.add_row()
        set_row_cant_split(row)
        cells = row.cells
        for idx, value in enumerate(values):
            cells[idx].text = str(value)
            if widths:
                set_cell_width(cells[idx], widths[idx])
            if row_idx % 2 == 1:
                set_cell_shading(cells[idx], COLOR_BLUE_PALE)
            format_cell(cells[idx], center=idx in center_cols, font_size=font_size)
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(0)
    return table


def add_hyperlink(paragraph, text, url):
    part = paragraph.part
    rid = part.relate_to(url, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", is_external=True)
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("r:id"), rid)
    new_run = OxmlElement("w:r")
    r_pr = OxmlElement("w:rPr")
    color = OxmlElement("w:color")
    color.set(qn("w:val"), COLOR_NAVY)
    r_pr.append(color)
    underline = OxmlElement("w:u")
    underline.set(qn("w:val"), "single")
    r_pr.append(underline)
    r_fonts = OxmlElement("w:rFonts")
    r_fonts.set(qn("w:eastAsia"), FONT_BODY)
    r_fonts.set(qn("w:ascii"), "Arial")
    r_fonts.set(qn("w:hAnsi"), "Arial")
    r_pr.append(r_fonts)
    new_run.append(r_pr)
    text_node = OxmlElement("w:t")
    text_node.text = text
    new_run.append(text_node)
    hyperlink.append(new_run)
    paragraph._p.append(hyperlink)
    return hyperlink


def add_paragraph(doc, text="", bold_lead=None, style=None, before=0, after=6, keep=False):
    p = doc.add_paragraph(style=style)
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.25
    p.paragraph_format.keep_with_next = keep
    if bold_lead and text.startswith(bold_lead):
        first = p.add_run(bold_lead)
        set_run_font(first, FONT_BODY, 10.8, True)
        rest = p.add_run(text[len(bold_lead):])
        set_run_font(rest, FONT_BODY, 10.8)
    else:
        run = p.add_run(text)
        set_run_font(run, FONT_BODY, 10.8)
    return p


def add_bullet(doc, text, level=0):
    style = "List Bullet" if level == 0 else "List Bullet 2"
    p = add_paragraph(doc, text, style=style, after=3)
    return p


def add_number(doc, text, level=0):
    style = "List Number" if level == 0 else "List Number 2"
    p = add_paragraph(doc, text, style=style, after=3)
    return p


def add_heading(doc, text, level=1):
    p = doc.add_paragraph(style=f"Heading {level}")
    p.paragraph_format.keep_with_next = True
    p.paragraph_format.space_before = Pt(12 if level == 1 else 8)
    p.paragraph_format.space_after = Pt(5)
    r = p.add_run(text)
    set_run_font(r, FONT_HEAD, 15 if level == 1 else 12.2, True, "000000")
    return p


def add_page_number(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run("第 ")
    set_run_font(run, FONT_BODY, 8.5, False, COLOR_TEXT_GRAY)
    fld_char1 = OxmlElement("w:fldChar")
    fld_char1.set(qn("w:fldCharType"), "begin")
    instr_text = OxmlElement("w:instrText")
    instr_text.set(qn("xml:space"), "preserve")
    instr_text.text = " PAGE "
    fld_char2 = OxmlElement("w:fldChar")
    fld_char2.set(qn("w:fldCharType"), "end")
    run._r.append(fld_char1)
    run._r.append(instr_text)
    run._r.append(fld_char2)
    run2 = paragraph.add_run(" 页")
    set_run_font(run2, FONT_BODY, 8.5, False, COLOR_TEXT_GRAY)


def setup_styles(doc):
    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = FONT_BODY
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_BODY)
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Arial")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Arial")
    normal.font.size = Pt(10.8)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.25

    title = styles["Title"]
    title.font.name = FONT_HEAD
    title._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_HEAD)
    title._element.rPr.rFonts.set(qn("w:ascii"), "Arial")
    title._element.rPr.rFonts.set(qn("w:hAnsi"), "Arial")
    title.font.size = Pt(25)
    title.font.bold = True
    title.font.color.rgb = RGBColor(0, 0, 0)
    # LibreOffice applies a theme underline to Word's built-in Title style.
    # Remove it so the cover stays clean in both Word and PDF rendering.
    title_p_pr = title._element.get_or_add_pPr()
    title_border = title_p_pr.find(qn("w:pBdr"))
    if title_border is not None:
        title_p_pr.remove(title_border)

    if "Document Subtitle" not in styles:
        subtitle = styles.add_style("Document Subtitle", WD_STYLE_TYPE.PARAGRAPH)
    else:
        subtitle = styles["Document Subtitle"]
    subtitle.font.name = FONT_BODY
    subtitle._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_BODY)
    subtitle.font.size = Pt(12)
    subtitle.font.color.rgb = RGBColor.from_string(COLOR_TEXT_GRAY)

    for level, size in ((1, 15), (2, 12.2), (3, 11)):
        style = styles[f"Heading {level}"]
        style.font.name = FONT_HEAD
        style._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_HEAD)
        style._element.rPr.rFonts.set(qn("w:ascii"), "Arial")
        style._element.rPr.rFonts.set(qn("w:hAnsi"), "Arial")
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor(0, 0, 0)
        style.paragraph_format.keep_with_next = True

    for name in ("List Bullet", "List Bullet 2", "List Number", "List Number 2"):
        style = styles[name]
        style.font.name = FONT_BODY
        style._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_BODY)
        style.font.size = Pt(10.6)


def build_document():
    doc = Document()
    setup_styles(doc)

    section = doc.sections[0]
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(0.72)
    section.bottom_margin = Inches(0.68)
    section.left_margin = Inches(0.78)
    section.right_margin = Inches(0.78)
    section.header_distance = Inches(0.3)
    section.footer_distance = Inches(0.3)
    add_page_number(section.footer.paragraphs[0])

    # Cover and decision summary
    title = doc.add_paragraph(style="Title")
    title.alignment = WD_ALIGN_PARAGRAPH.LEFT
    title.paragraph_format.space_before = Pt(28)
    title.paragraph_format.space_after = Pt(10)
    r = title.add_run("个人食品决策助手第一阶段项目落实计划书")
    set_run_font(r, FONT_HEAD, 25, True, "000000")

    subtitle = doc.add_paragraph(style="Document Subtitle")
    subtitle.paragraph_format.space_after = Pt(18)
    sr = subtitle.add_run("版本 0.1  原生 iOS 个人自用项目")
    set_run_font(sr, FONT_BODY, 12, False, COLOR_TEXT_GRAY)

    metadata_rows = [
        ("计划日期", "2026 年 9 月 26 日"),
        ("目标设备", "iPhone 16 Pro Max  iOS 26.6.2  Apple Watch"),
        ("用户目标", "健身小白阶段的减脂增肌  同时处理 LDL 约束  异维 A 酸疗程和清真饮食"),
        ("第一阶段周期", "6 周  单人业余开发的可验证版本"),
    ]
    meta = doc.add_table(rows=0, cols=2)
    meta.alignment = WD_TABLE_ALIGNMENT.LEFT
    meta.autofit = False
    set_table_borders(meta, color=COLOR_BORDER, size="4")
    meta_header = meta.add_row()
    set_repeat_table_header(meta_header)
    set_row_cant_split(meta_header)
    for idx, text in enumerate(("项目概况", "内容")):
        cell = meta_header.cells[idx]
        cell.text = text
        set_cell_width(cell, (1.25, 5.55)[idx])
        set_cell_shading(cell, COLOR_NAVY)
        format_cell(cell, header=True, center=True, font_size=9.2)
    for idx, (key, value) in enumerate(metadata_rows):
        row = meta.add_row()
        set_row_cant_split(row)
        cells = row.cells
        cells[0].text = key
        cells[1].text = value
        set_cell_width(cells[0], 1.25)
        set_cell_width(cells[1], 5.55)
        set_cell_shading(cells[0], COLOR_BLUE)
        format_cell(cells[0], center=True, font_size=9.5)
        format_cell(cells[1], center=False, font_size=9.5)
        for run in cells[0].paragraphs[0].runs:
            run.bold = True
    doc.add_paragraph()

    add_heading(doc, "项目结论", 1)
    add_paragraph(
        doc,
        "第一阶段应同时完成两个高频闭环。第一个闭环是在超市扫描条码或食品标签，按个人约束给出可追溯的购买判断；第二个闭环是称重记录中餐家常菜，计算每日热量、蛋白质、饱和脂肪和纤维。训练组次、社区、跨国家规则和完整 Apple Watch App 暂不进入第一阶段。",
    )
    add_paragraph(
        doc,
        "外部评审中关于数据源、AI 分工、称重减负、规则版本和 HealthKit 去重的建议直接进入计划。涉及药物、维生素 A 形态、清真教法判断和实验室指标解释的内容只建立数据结构，不在未经核验时生成硬性医学结论。",
    )

    decision_rows = [
        ("第一优先", "超市食品标签扫描和购买判断"),
        ("第二优先", "中餐菜谱称重和滚动营养额度"),
        ("技术原则", "AI 负责识别和归一化  本地代码负责计算和红灯规则"),
        ("隐私原则", "第三方模型只接收必要图片  不接收 LDL 用药和清真档案"),
        ("延期内容", "训练模块  Watch App  社区  自动医疗解释"),
    ]
    add_table(doc, ["项目决策", "落实结果"], decision_rows, widths=[1.35, 5.45], center_cols=[0], font_size=9.7)

    doc.add_page_break()

    # Section 1
    add_heading(doc, "1 项目范围和成功标准", 1)
    add_heading(doc, "1.1 第一阶段用户", 2)
    add_paragraph(
        doc,
        "该版本只服务一个明确用户。用户在英国生活，主要吃中餐家常菜和外卖，愿意称重换取精度，正在进行减脂增肌，并需要把 LDL 偏高、异维 A 酸疗程和清真偏好带入日常购买决策。产品无需支持多账号、教练后台或公开社区。",
    )

    add_heading(doc, "1.2 第一阶段目标", 2)
    for item in [
        "在超市对准条码或标签后，给出值得买、有更好选择、不建议、不符合约束或无法判断五种结论。",
        "保存已经扫描和人工核对过的商品，同一商品再次扫描时直接命中本地记录。",
        "支持原材料重量、容器皮重、成品总重和个人食用重量，准确分摊家常菜营养。",
        "显示每日以及 3 天和 7 天滚动的热量、蛋白质、饱和脂肪和纤维。",
        "读取 Apple Health 的步数、活动能量、训练和体重，但不把运动热量直接加入可吃额度。",
    ]:
        add_bullet(doc, item)

    add_heading(doc, "1.3 可验证的成功标准", 2)
    success_rows = [
        ("超市扫描", "本地已知商品 5 秒内出结果  新标签在用户确认后 30 秒内完成"),
        ("安全边界", "测试集中硬约束不得出现错误绿灯  信息缺失必须返回无法判断"),
        ("称重记录", "复用菜谱时 30 秒内完成一餐记录  首次建菜谱控制在 3 分钟内"),
        ("数据一致性", "同一餐编辑和删除后 SwiftData 与 HealthKit 无重复样本"),
        ("个人使用", "连续 2 周至少每周完成 5 天饮食记录和 2 次超市扫描"),
    ]
    add_table(doc, ["指标", "验收标准"], success_rows, widths=[1.35, 5.45], center_cols=[0], font_size=9.6)

    add_heading(doc, "1.4 第一阶段不做的内容", 2)
    for item in [
        "训练动作库、渐进超负荷和独立 Apple Watch 训练界面。训练先由现有 App 或 Apple Watch 记录。",
        "社区、好友、公开商品评论和众包审核。",
        "跨马来西亚和中国的完整标签制度。数据模型保留地区字段，但 v0.1 只优化英国标签。",
        "对 LDL、甘油三酯、肝功能或肌肉症状作诊断和治疗建议。",
        "从互联网自动推荐具体商品并声称当地一定有售。替代建议只来自眼前对比、本地商品库和通用替换规则。",
    ]:
        add_bullet(doc, item)

    # Section 2
    add_heading(doc, "2 外部意见的处理决定", 1)
    add_paragraph(
        doc,
        "外部意见多数可转化为实施任务，但医学规则和教法判断不能仅凭一份评审文本进入生产逻辑。以下表格记录每项建议的处理结果。",
    )

    action_rows = [
        ("营养数据分层", "立即采用", "v0.1", "CoFID 和 USDA 处理通用食材  Open Food Facts 处理条码商品  人工记录补中式常用食材"),
        ("AI 只识别不计算", "立即采用", "v0.1", "模型返回结构化候选和置信度  热量和营养素由本地数据库按克数计算"),
        ("医疗档案不发给第三方", "立即采用", "v0.1", "只上传必要图片和最小提示  约束匹配全部在设备执行"),
        ("离线 OCR 和规则", "立即采用", "v0.1", "Vision 识别标签  本地规则输出硬约束  网络只用于商品库和困难图片兜底"),
        ("容器皮重和差值法", "立即采用", "v0.1", "保存常用容器皮重  支持总量法  差值法  比例法"),
        ("剩菜和汤汁修正", "立即采用", "v0.1", "保存剩余重量和营养  汤汁扣除作为可选高级修正"),
        ("菜谱稳定期", "立即采用", "v0.1", "同一菜谱完成 3 次后建议保存平均成品率和常用份量"),
        ("规则版本和有效期", "立即采用", "v0.1", "每条规则保存来源  版本  启用日期  结束日期和用户确认状态"),
        ("清真四态", "修改后采用", "v0.1", "状态改为已认证  成分未见冲突但无认证  存疑  不符合  不由 App 代替用户作教法判断"),
        ("维生素 A 形态和换算", "验证后采用", "v0.1", "先建立形态和单位模型  具体换算及红灯清单须以药品说明书或药师确认结果为准"),
        ("实验室指标时间线", "限制性采用", "v0.2", "允许手工记录 LDL 甘油三酯和肝功能  仅展示时间线  不自动解释治疗效果"),
        ("连锁外卖官方热量", "立即采用", "v0.2", "优先保存菜单公开热量及份量来源  同店同菜复用上次修正结果"),
        ("HealthKit 同步标识", "立即采用", "v0.1", "使用 SyncIdentifier 和 SyncVersion 处理更新  每餐用 food correlation 打包营养样本"),
        ("HealthKit 活动去重", "立即采用", "v0.1", "使用统计查询读取步数和活动能量  不手工累加 iPhone 与 Watch 来源"),
        ("SwiftData 迁移", "立即采用", "v0.1", "第一天使用 VersionedSchema  营养素按 ID 扩展  同时保存输入快照和计算结果"),
        ("CloudKit", "预留但不开启", "v0.1", "模型保持可同步设计  第一阶段以本地存储和 JSON CSV 导出为主"),
        ("AlarmKit 休息计时", "延后", "v0.3", "API 可用  但训练不在第一阶段范围"),
    ]
    add_table(
        doc,
        ["建议", "决定", "版本", "落实方式"],
        action_rows,
        widths=[1.35, 1.0, 0.62, 3.85],
        center_cols=[1, 2],
        font_size=8.65,
    )

    add_heading(doc, "2.1 暂不写成硬规则的内容", 2)
    for item in [
        "动物肝脏不会仅因服用异维 A 酸而自动判为禁食。NHS 的通用指导是避免维生素 A 补剂并正常饮食；只有医生明确要求时才增加食品限制。",
        "β 胡萝卜素、鱼肝油和不同视黄醇单位的处理需要分别核对，不使用一个通用换算覆盖所有形态。",
        "明胶、E471、乳清和香精等只触发存疑或需要来源证明，不能脱离来源直接判为不符合清真。",
        "营养表的 4 4 9 能量公式只作为 OCR 质量提示。糖醇、纤维、四舍五入和有机酸会造成差异，因此不能据此拒绝商品。",
        "实验室指标可以记录，但 App 不判断异维 A 酸是否导致某次 LDL 或甘油三酯变化。",
    ]:
        add_bullet(doc, item)

    # Section 3
    add_heading(doc, "3 v0.1 产品流程", 1)
    add_heading(doc, "3.1 超市标签扫描", 2)
    scan_steps = [
        "先扫描条码。依次查询本地商品库和 Open Food Facts。",
        "未命中或数据不完整时拍摄营养表、配料表、认证标志和可选价签。",
        "Vision 在设备上识别表格、文字和条码。解析器统一 kcal、kJ、每份、每 100g、盐和钠等字段。",
        "用户检查关键数字。饱和脂肪大于总脂肪、糖大于碳水或能量差异异常时必须提示复核。",
        "本地约束引擎依次执行药物与补剂规则、过敏原、清真状态和数据完整度判断。",
        "通过硬约束后，按品类计算蛋白密度、饱和脂肪、纤维、盐、实际份量和价格指标。",
        "结果保存到个人商品库。用户可连续扫描 2 到 4 个商品并排比较。",
    ]
    for step in scan_steps:
        add_number(doc, step)

    result_rows = [
        ("值得买", "满足个人硬约束  同品类主要指标较好  数据完整"),
        ("能买但有更好选择", "满足硬约束  但至少一个关键指标明显落后于本地候选"),
        ("不建议", "没有安全冲突  但与减脂增肌或 LDL 目标不匹配"),
        ("不符合约束", "命中已经核验并由用户启用的硬约束"),
        ("无法判断", "标签不清  关键字段缺失  认证来源不明或规则证据不足"),
    ]
    add_table(doc, ["结果", "使用条件"], result_rows, widths=[1.55, 5.25], center_cols=[0], font_size=9.5)

    add_heading(doc, "3.2 家常菜称重", 2)
    for step in [
        "选择菜谱或创建新菜  通过大号数字键盘录入食材克数。",
        "选择已保存容器或锅具  系统自动扣除皮重。",
        "记录成品总重量。成品重量会自然包含烹饪失水的影响。",
        "按个人食用重量、整盘前后差值或比例分配个人份量。",
        "如有大量汤汁或油留在盘中  用户可选择扣除剩余汤汁重量。",
        "保存剩余重量。下次食用时可以重新称量  系统按剩余营养重新分配。",
    ]:
        add_number(doc, step)

    formula = add_paragraph(doc, "个人摄入营养 = 全锅营养 × 个人食用重量 ÷ 成品总重量", before=3, after=8)
    formula.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for run in formula.runs:
        set_run_font(run, "Arial", 11, True, COLOR_NAVY)

    add_heading(doc, "3.3 今日页", 2)
    for item in [
        "显示热量、蛋白质、饱和脂肪和纤维的今日值以及 3 天和 7 天平均。",
        "显示步数、活动能量和 Apple Watch 训练，但运动热量只作背景信息。",
        "建议优先从个人菜谱和已经核对过的商品库中生成。",
        "体重采用指数加权趋势并提示统一称重条件  早上如厕后进食前。",
    ]:
        add_bullet(doc, item)

    # Section 4
    add_heading(doc, "4 决策引擎和评分规则", 1)
    add_heading(doc, "4.1 判断顺序", 2)
    logic_rows = [
        ("1", "数据完整度", "缺少必须字段时返回无法判断"),
        ("2", "已核验硬约束", "命中后返回不符合约束  不再被营养分数覆盖"),
        ("3", "清真状态", "按用户接受的认证机构和成分证据分级"),
        ("4", "品类评分", "仅与相同购买目的的商品比较"),
        ("5", "替代建议", "从同货架对比  本地历史和通用规则中选择"),
    ]
    add_table(doc, ["顺序", "检查", "处理"], logic_rows, widths=[0.65, 1.6, 4.55], center_cols=[0, 1], font_size=9.5)

    add_heading(doc, "4.2 第一批品类指标", 2)
    category_rows = [
        ("蛋白来源", "每 100 kcal 蛋白质  每 10g 蛋白带来的饱和脂肪  每 10g 蛋白价格"),
        ("主食", "每 100g 纤维  盐  糖  用户实际一次份量"),
        ("乳制品", "蛋白密度  每份饱和脂肪  添加糖"),
        ("零食和蛋白棒", "每份热量  蛋白密度  饱和脂肪  糖和糖醇"),
        ("酱料调味", "按一次实际用量计算盐和糖  不按整瓶评分"),
        ("食用油和涂抹脂肪", "饱和脂肪比例  实际用量  油种"),
    ]
    add_table(doc, ["品类", "主要指标"], category_rows, widths=[1.55, 5.25], center_cols=[0], font_size=9.45)
    add_paragraph(
        doc,
        "所有阈值和权重放在可版本化配置中，不写死在界面或网络请求里。第一阶段使用通用参考线和用户自定义目标，完成 30 到 50 个真实商品测试后再调整权重。",
    )

    add_heading(doc, "4.3 医疗约束边界", 2)
    add_paragraph(
        doc,
        "异维 A 酸规则只对已经核验的补剂成分生成红灯。普通食品天然含维生素 A 不自动禁食。药物疗程规则必须有启用日期和结束日期，疗程结束后提示用户重新确认。实验室数据仅用于记录和与医生沟通，不进入自动诊断。",
    )

    # Section 5
    add_heading(doc, "5 数据和技术架构", 1)
    add_heading(doc, "5.1 技术栈", 2)
    tech_rows = [
        ("界面", "SwiftUI  @Observable"),
        ("业务数据", "SwiftData  VersionedSchema  本地优先"),
        ("扫描", "Vision RecognizeDocumentsRequest  条码检测  PhotosUI"),
        ("健康数据", "HealthKit  统计查询  food correlation  同步标识"),
        ("网络", "URLSession  Open Food Facts  USDA FoodData Central"),
        ("AI", "FoodVisionProvider 协议  第三方视觉模型仅作困难图片和外卖兜底"),
        ("安全", "Keychain 保存 API Key  图片按需压缩和裁剪"),
        ("导出", "JSON 全量备份  CSV 饮食和商品记录"),
    ]
    add_table(doc, ["层", "选择"], tech_rows, widths=[1.3, 5.5], center_cols=[0], font_size=9.5)

    add_heading(doc, "5.2 数据源", 2)
    source_rows = [
        ("CoFID", "英国常见食材及营养", "本地导入经过筛选的数据  保存数据版本"),
        ("USDA FoodData Central", "通用食材和补充微量营养", "远程搜索后保存快照  API Key 放入 Keychain"),
        ("Open Food Facts", "英国条码商品", "先查条码  保存原始来源和人工核对状态"),
        ("个人食材和菜谱", "中式食材  外卖  常做菜", "最高优先级  允许纠错和复用"),
        ("商品标签", "具体品牌的配料和营养", "产品特定判断时优先于外部数据库"),
    ]
    add_table(doc, ["来源", "用途", "落地要求"], source_rows, widths=[1.55, 2.0, 3.25], center_cols=[0], font_size=9.2)

    add_heading(doc, "5.3 AI 和本地代码的边界", 2)
    boundary_rows = [
        ("AI 可以做", "识别菜品  OCR 纠错  商品分类  成分名称归一化  输出候选和置信度"),
        ("AI 不可以做", "直接给最终热量  判断药物安全  判定清真  修改用户目标"),
        ("本地代码负责", "单位换算  营养计算  硬约束  评分  滚动统计  HealthKit 去重"),
        ("上传边界", "只上传完成任务所需的图片  不上传用户医疗和宗教档案"),
    ]
    add_table(doc, ["边界", "规定"], boundary_rows, widths=[1.4, 5.4], center_cols=[0], font_size=9.45)

    add_heading(doc, "5.4 核心数据模型", 2)
    model_rows = [
        ("ConstraintProfile", "个人目标  药物疗程  清真偏好  过敏原  用户确认"),
        ("ConstraintRule", "规则类型  证据来源  版本  有效期  阈值  严重度"),
        ("FoodItem", "来源 ID  名称  品类  每 100g 营养  数据版本  核对状态"),
        ("ProductSnapshot", "条码  标签原文  配料  营养  价格  店铺  日期  照片"),
        ("RecipeBatch", "食材输入  容器皮重  成品重  剩余重  成品率"),
        ("MealLog", "餐次  食用重量  营养快照  估算范围  HealthKit 同步版本"),
        ("DailySnapshot", "每日摄入  体重趋势  HealthKit 活动  数据完整度"),
        ("Assessment", "结论  命中规则  评分  不确定项  数据来源"),
    ]
    add_table(doc, ["模型", "关键内容"], model_rows, widths=[1.65, 5.15], center_cols=[0], font_size=9.2)

    # Section 6
    add_heading(doc, "6 六周实施计划", 1)
    schedule_rows = [
        ("第 1 周", "工程基础和规则骨架", "建立 Xcode 项目  SwiftUI 导航  Repository 协议  VersionedSchema  约束档案  本地规则 JSON  核心单元测试", "可录入个人约束  可运行示例硬规则  数据迁移框架就绪"),
        ("第 2 周", "营养数据层", "导入 CoFID 子集  接入 USDA 和 Open Food Facts  统一营养素 ID  建立 FoodItem 和 ProductSnapshot  本地缓存", "条码查询和食材搜索可用  每条数据可追溯到来源和版本"),
        ("第 3 周", "标签扫描", "接入 Vision 文档识别和条码  解析英国营养表  单位换算  OCR 校验  人工确认页", "30 个真实标签可完成识别  异常值必须触发复核"),
        ("第 4 周", "购买判断和对比", "实现硬约束顺序  清真四态  六类商品评分  五档结果卡  本地商品库  2 到 4 件并排比较", "不得错误绿灯  替代项只来自真实候选  每条判断显示依据"),
        ("第 5 周", "称重饮食和今日页", "实现容器皮重  菜谱批次  成品重  食用重  差值和比例法  剩菜  稳定期  3 天和 7 天滚动指标", "公式单元测试通过  复用菜谱可在 30 秒内记一餐"),
        ("第 6 周", "HealthKit 和试用", "读取步数活动训练体重  写入 food correlation  同步更新删除  JSON CSV 导出  50 件商品和 10 个菜谱测试  连续两周个人试用", "无重复 HealthKit 数据  崩溃和阻塞问题清零  形成 v0.2 问题清单"),
    ]
    add_table(
        doc,
        ["周期", "目标", "主要任务", "完成定义"],
        schedule_rows,
        widths=[0.75, 1.25, 3.0, 1.8],
        center_cols=[0],
        font_size=8.6,
    )

    add_heading(doc, "6.1 每周交付纪律", 2)
    for item in [
        "每周只交付一个可从界面走通的纵向闭环  不只完成孤立的数据模型。",
        "规则、换算和称重公式必须有单元测试  医疗规则还要记录依据和人工确认状态。",
        "每周末用真实商品和真实做饭数据试用  将修正记录转成下一周任务。",
        "任何需要用户输入的关键步骤都先测操作成本  再增加更多营养指标。",
    ]:
        add_bullet(doc, item)

    # Section 7
    add_heading(doc, "7 验收和测试计划", 1)
    test_rows = [
        ("规则测试", "含维生素 A 的补剂样例  标签不完整样例  过敏原样例  清真认证和存疑成分样例", "硬约束不漏报  无证据时不输出安全"),
        ("OCR 测试", "Tesco  Sainsbury's  Aldi  Lidl  亚洲超市包装  反光和弯曲包装", "关键字段可人工确认  解析失败可恢复"),
        ("营养计算", "kJ 与 kcal  每份与每 100g  盐与钠  糖醇和纤维", "换算可复现  不因近似公式错误拒绝商品"),
        ("称重测试", "容器皮重  一锅多餐  差值法  比例法  剩菜复热失水", "个人营养分配守恒  修改后历史正确"),
        ("HealthKit", "新增  编辑  删除同一餐  Watch 和 iPhone 同时有活动数据", "样本无重复  活动能量不与训练重复相加"),
        ("隐私", "网络抓包和日志检查", "图片之外不发送医疗  清真或体重档案  日志不包含 API Key"),
    ]
    add_table(doc, ["测试域", "测试集", "通过条件"], test_rows, widths=[1.1, 3.0, 2.7], center_cols=[0], font_size=8.95)

    add_heading(doc, "7.1 发布前阻断条件", 2)
    for item in [
        "任何已知硬约束存在错误绿灯。",
        "缺少营养表或配料表时仍给出确定购买结论。",
        "同一餐编辑后在 HealthKit 出现重复记录。",
        "第三方请求包含用药、LDL、清真标准或完整用户档案。",
        "计算结果不能追溯到食材输入、克数和数据库版本。",
    ]:
        add_bullet(doc, item)

    # Section 8
    add_heading(doc, "8 风险和控制", 1)
    risk_rows = [
        ("高精度记录负担过大", "高", "菜谱复用  保存容器皮重  3 次后进入稳定期  后续增加语音和 App Intents"),
        ("众包商品数据错误", "高", "标签优先  保存来源和核对状态  关键值由用户确认"),
        ("医疗规则误判", "高", "仅启用有来源且由用户确认的规则  信息不足返回无法判断"),
        ("清真状态过度推断", "高", "认证与成分分开  存疑成分不直接判定  用户选择认可机构"),
        ("OCR 在货架环境失败", "中", "支持多张图片  手工修正  离线重试  保留原图高亮证据"),
        ("范围持续扩大", "高", "训练和跨境规则进入待办  v0.1 只围绕购买和称重两个闭环"),
        ("本地数据丢失", "中", "第 6 周实现全量 JSON 导出  数据模型保持 CloudKit 兼容"),
        ("外卖估值偏差", "中", "优先用连锁店公开热量  保存同店同菜修正  用范围而非单点值"),
    ]
    add_table(doc, ["风险", "等级", "控制措施"], risk_rows, widths=[2.0, 0.65, 4.15], center_cols=[1], font_size=9.0)

    # Section 9
    add_heading(doc, "9 后续版本", 1)
    roadmap_rows = [
        ("v0.2", "外卖和健康趋势", "连锁菜单热量  同店同菜复用  第三方餐食识别  LDL 甘油三酯和肝功能时间线  CloudKit 决策"),
        ("v0.3", "训练联动", "动作模板  重量次数 RPE  AlarmKit 休息计时  Watch 训练重叠检查  训练日饮食调整"),
        ("v0.4", "效率和扩展", "语音称重  App Intents  控制中心入口  更多地区标签  更成熟的同类替代推荐"),
    ]
    add_table(doc, ["版本", "主题", "内容"], roadmap_rows, widths=[0.75, 1.65, 4.4], center_cols=[0], font_size=9.4)

    add_heading(doc, "10 第一周启动清单", 1)
    first_week = [
        "创建原生 SwiftUI Xcode 项目并确定 Bundle Identifier。",
        "建立 Core  Data  Features  Integrations  Resources  Tests 六个目录。",
        "定义 NutrientID  FoodItem  ConstraintRule  ConstraintProfile  ProductSnapshot 第一版模型。",
        "启用 SwiftData VersionedSchema v1  避免 unique 约束并为未来 CloudKit 保留空间。",
        "完成规则 JSON 格式  包含来源 URL  版本  有效期  严重度和用户确认。",
        "实现三个基础用例测试  含维生素 A 补剂  信息不足  清真状态未知。",
        "导入 20 个常用中式食材和 10 个英国包装商品作为种子数据。",
        "制作约束档案和商品结果卡的静态 SwiftUI 原型。",
        "建立问题清单  记录仍需医生药师确认的规则和仍需技术验证的 API。",
    ]
    for item in first_week:
        add_bullet(doc, item)

    add_heading(doc, "10.1 启动前需要补齐的个人数据", 2)
    for item in [
        "年龄  身高  当前体重  目标体重和每周训练次数。",
        "医生或药师对异维 A 酸  补剂和饮食的明确要求原文。",
        "如有  医生给出的饱和脂肪或其他营养目标。",
        "认可的清真认证机构和对未认证商品的接受标准。",
        "最常做的 10 道菜  最常购买的 20 件商品和最常点的外卖店。",
    ]:
        add_bullet(doc, item)

    # References
    add_heading(doc, "依据和技术参考", 1)
    refs = [
        ("Apple Vision RecognizeDocumentsRequest", "https://developer.apple.com/documentation/vision/recognizedocumentsrequest"),
        ("Apple HealthKit HKCorrelation", "https://developer.apple.com/documentation/healthkit/hkcorrelation"),
        ("Apple HealthKit Sync Identifier", "https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier"),
        ("Apple HealthKit Queries", "https://developer.apple.com/documentation/healthkit/queries"),
        ("Apple AlarmKit", "https://developer.apple.com/documentation/alarmkit"),
        ("英国 CoFID 数据集", "https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid"),
        ("英格兰大型餐饮企业热量标示实施指南", "https://www.gov.uk/government/publications/calorie-labelling-in-the-out-of-home-sector/calorie-labelling-in-the-out-of-home-sector-implementation-guidance"),
        ("NHS 异维 A 酸说明", "https://www.nhs.uk/medicines/isotretinoin-roaccutane/"),
        ("英国异维 A 酸药品特性摘要", "https://www.medicines.org.uk/emc/product/100769/smpc"),
        ("USDA FoodData Central API", "https://fdc.nal.usda.gov/api-guide/"),
        ("Open Food Facts API", "https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/"),
    ]
    for idx, (name, url) in enumerate(refs, 1):
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(4)
        p.paragraph_format.left_indent = Inches(0.12)
        r = p.add_run(f"{idx}. ")
        set_run_font(r, FONT_BODY, 9.5)
        add_hyperlink(p, name, url)

    add_paragraph(
        doc,
        "本计划中的医学边界用于限制软件行为，不替代医生或药师意见。任何新增红灯规则都必须同时具备明确来源、适用范围、有效期和用户确认。",
        before=8,
        after=0,
    )

    # Keep tables from hugging preceding paragraphs and normalize document properties.
    core_props = doc.core_properties
    core_props.title = "个人食品决策助手第一阶段项目落实计划书"
    core_props.subject = "原生 iOS 个人食品决策助手 v0.1 实施计划"
    core_props.author = ""
    core_props.keywords = "iOS SwiftUI 食品标签 中餐称重 HealthKit"

    doc.save(OUTPUT_PATH)
    return OUTPUT_PATH


if __name__ == "__main__":
    path = build_document()
    print(path.resolve())
