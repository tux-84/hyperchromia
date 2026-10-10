#!/usr/bin/env python3
import sys

template_path, nav_path, content_path, title, last_updated, out_path = sys.argv[1:7]

page = open(template_path, encoding="utf-8").read()
nav = open(nav_path, encoding="utf-8").read()
content = open(content_path, encoding="utf-8").read()

page = page.replace("{{TITLE}}", title)
page = page.replace("{{LAST_UPDATED}}", last_updated)
page = page.replace("{{NAV}}", nav)
page = page.replace("{{CONTENT}}", content)

open(out_path, "w", encoding="utf-8").write(page)
