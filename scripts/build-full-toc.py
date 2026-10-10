#!/usr/bin/env python3
import re
import sys


def strip_tags(text):
    return re.sub(r"<[^>]+>", "", text)


def heading_tree(content):
    headings = re.findall(r'<h([23]) id="([^"]+)">(.*?)</h\1>', content, re.S)
    tree = []
    current = None
    for level, hid, text in headings:
        if level == "2" or current is None:
            current = {"hid": hid, "text": strip_tags(text), "children": []}
            tree.append(current)
        else:
            current["children"].append({"hid": hid, "text": strip_tags(text)})
    return tree


def render_chapter_body(tree, slug):
    if not tree:
        return ""
    out = ["<ol>"]
    for node in tree:
        out.append(f'<li><a href="{slug}.html#{node["hid"]}">{node["text"]}</a>')
        if node["children"]:
            out.append("<ol>")
            for child in node["children"]:
                out.append(f'<li><a href="{slug}.html#{child["hid"]}">{child["text"]}</a></li>')
            out.append("</ol>")
        out.append("</li>")
    out.append("</ol>")
    return "".join(out)


lines = ["<h1>Table of Contents</h1>", '<ol class="full-toc">']
for arg in sys.argv[1:]:
    slug, title, content_path = arg.split(":", 2)
    content = open(content_path, encoding="utf-8").read()
    tree = heading_tree(content)
    lines.append(f'<li><a href="{slug}.html">{title}</a>{render_chapter_body(tree, slug)}</li>')
lines.append("</ol>")

sys.stdout.write("\n".join(lines))
