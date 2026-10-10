#!/usr/bin/env python3
import re
import sys

template_path, nav_path, content_path, title, last_updated, out_path = sys.argv[1:7]

page = open(template_path, encoding="utf-8").read()
nav = open(nav_path, encoding="utf-8").read()
content = open(content_path, encoding="utf-8").read()

headings = re.findall(r'<h([23]) id="([^"]+)">(.*?)</h\1>', content, re.S)
toc_items = "".join(
    f'<li class="toc-level-{level}"><a href="#{hid}">{re.sub(r"<[^>]+>", "", text)}</a></li>\n'
    for level, hid, text in headings
)
page_toc = (
    f'<nav class="page-toc"><strong>On this page</strong><ul>\n{toc_items}</ul></nav>'
    if toc_items
    else ""
)

page = page.replace("{{TITLE}}", title)
page = page.replace("{{LAST_UPDATED}}", last_updated)
page = page.replace("{{NAV}}", nav)
page = page.replace("{{PAGE_TOC}}", page_toc)
page = page.replace("{{CONTENT}}", content)

open(out_path, "w", encoding="utf-8").write(page)
