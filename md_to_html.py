#!/usr/bin/env python3
"""Simple Markdown to HTML converter for REPORT.md"""

import re
import sys
import base64
from pathlib import Path
from PIL import Image
import io

def image_to_data_uri(img_path):
    """Convert image file to base64 data URI, keeping original resolution"""
    try:
        # Read image without resizing
        with open(img_path, 'rb') as f:
            img_data = f.read()

        b64_data = base64.b64encode(img_data).decode('utf-8')
        return f'data:image/png;base64,{b64_data}'
    except Exception as e:
        print(f"Warning: Could not embed image {img_path}: {e}")
        return img_path

def md_to_html(md_content):
    """Convert basic markdown to HTML"""
    html = []
    html.append('<!DOCTYPE html>')
    html.append('<html>')
    html.append('<head>')
    html.append('<meta charset="utf-8">')
    html.append('<title>InnoDB Thread Concurrency Performance Analysis Report</title>')
    html.append('<style>')
    html.append('body { font-family: Arial, sans-serif; width: 100%; max-width: 100%; margin: 0; padding: 0.4in; line-height: 1.3; box-sizing: border-box; }')
    html.append('h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; margin-bottom: 10px; }')
    html.append('h2 { color: #34495e; border-bottom: 2px solid #95a5a6; padding-bottom: 8px; margin-top: 30px; }')
    html.append('h3 { color: #555; margin-top: 25px; }')
    html.append('h4 { color: #666; margin-top: 20px; }')
    html.append('table { border-collapse: collapse; width: 100% !important; margin: 20px 0; table-layout: fixed; }')
    html.append('th, td { border: 1px solid #333; padding: 10px 12px; text-align: left; vertical-align: top; word-wrap: break-word; }')
    html.append('th { background-color: #3498db; color: white; font-weight: bold; text-align: center; }')
    html.append('tbody tr:nth-child(even) { background-color: #f9f9f9; }')
    html.append('tbody tr:nth-child(odd) { background-color: #ffffff; }')
    html.append('code { background-color: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-family: monospace; }')
    html.append('pre { background-color: #f4f4f4; padding: 15px; border-radius: 5px; overflow-x: auto; line-height: 1.2; margin: 10px 0 0 0; }')
    html.append('pre code { background: none; padding: 0; line-height: 1.2; }')
    html.append('strong { color: #2c3e50; }')
    html.append('a { color: #3498db; text-decoration: none; }')
    html.append('a:hover { text-decoration: underline; }')
    html.append('img { max-width: 100%; height: auto; margin: 10px 0; border: 1px solid #ddd; display: block; }')
    html.append('ul, ol { margin: 15px 0; padding-left: 30px; }')
    html.append('li { margin: 8px 0; }')
    html.append('</style>')
    html.append('</head>')
    html.append('<body>')

    lines = md_content.split('\n')
    in_code_block = False
    in_table = False
    in_list = False
    prev_was_header = False
    prev_was_code_block = False

    i = 0
    while i < len(lines):
        line = lines[i]

        # Code blocks
        if line.startswith('```'):
            if in_code_block:
                html.append('</code></pre>')
                in_code_block = False
                prev_was_code_block = True
            else:
                html.append('<pre><code>')
                in_code_block = True
                prev_was_code_block = False
            i += 1
            continue

        if in_code_block:
            html.append(line.replace('<', '&lt;').replace('>', '&gt;'))
            i += 1
            continue

        # Headers
        if line.startswith('# '):
            html.append(f'<h1>{line[2:]}</h1>')
            prev_was_header = True
        elif line.startswith('## '):
            html.append(f'<h2>{line[3:]}</h2>')
            prev_was_header = True
        elif line.startswith('### '):
            html.append(f'<h3>{line[4:]}</h3>')
            prev_was_header = True
        elif line.startswith('#### '):
            html.append(f'<h4>{line[5:]}</h4>')
            prev_was_header = True
        # Images
        elif '![' in line:
            match = re.search(r'!\[([^\]]*)\]\(([^)]+)\)', line)
            if match:
                alt_text = match.group(1)
                img_src = match.group(2)
                # Convert relative paths to base64 data URIs
                if not img_src.startswith(('http://', 'https://', 'data:')):
                    img_src = image_to_data_uri(img_src)
                html.append(f'<p style="text-align: center;"><img src="{img_src}" alt="{alt_text}" width="7.64in" style="width: 7.64in; height: auto;"></p>')
        # Tables
        elif '|' in line and not line.strip().startswith('<!--'):
            if not in_table:
                html.append('<table width="100%" border="1" cellpadding="1" cellspacing="0" style="width: 100% !important;">')
                in_table = True
                # Check if next line is separator
                if i + 1 < len(lines) and '---' in lines[i + 1]:
                    html.append('<thead><tr>')
                    cells = [c.strip() for c in line.split('|')[1:-1]]
                    for cell in cells:
                        html.append(f'<th style="border: 1px solid #333; padding: 1px 2px; background-color: #3498db; color: white; font-weight: bold; text-align: center;">{process_inline_markdown(cell)}</th>')
                    html.append('</tr></thead><tbody>')
                    i += 2  # Skip separator line
                    continue
            else:
                html.append('<tr>')
                cells = [c.strip() for c in line.split('|')[1:-1]]
                for idx, cell in enumerate(cells):
                    # First column (engine names) gets larger font
                    font_size = 'font-size: 15px;' if idx == 0 else ''
                    html.append(f'<td style="border: 1px solid #333; padding: 1px 2px; text-align: left; vertical-align: top; {font_size}">{process_inline_markdown(cell)}</td>')
                html.append('</tr>')
        else:
            if in_table and '|' not in line:
                html.append('</tbody></table>')
                in_table = False

            # Lists
            if line.startswith('- ') or line.startswith('* '):
                if not in_list:
                    html.append('<ul>')
                    in_list = True
                html.append(f'<li>{process_inline_markdown(line[2:])}</li>')
            else:
                if in_list:
                    html.append('</ul>')
                    in_list = False

                # Regular paragraph
                if line.strip():
                    html.append(f'<p>{process_inline_markdown(line)}</p>')
                    prev_was_header = False
                    prev_was_code_block = False
                elif not in_code_block and not prev_was_header and not prev_was_code_block:
                    # Check if next non-empty line is a header
                    next_is_header = False
                    for j in range(i + 1, len(lines)):
                        if lines[j].strip():
                            if lines[j].startswith('#'):
                                next_is_header = True
                            break
                    # Only add <br> if next line is not a header
                    if not next_is_header:
                        html.append('<br>')
                else:
                    prev_was_header = False
                    if not in_code_block:
                        prev_was_code_block = False

        i += 1

    if in_table:
        html.append('</tbody></table>')
    if in_list:
        html.append('</ul>')

    html.append('</body>')
    html.append('</html>')

    return '\n'.join(html)

def process_inline_markdown(text):
    """Process inline markdown like bold, italic, code, links"""
    # Links [text](url)
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
    # Bold
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    # Inline code
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    return text

if __name__ == '__main__':
    with open('REPORT.md', 'r') as f:
        md_content = f.read()

    html_content = md_to_html(md_content)

    with open('test-report.html', 'w') as f:
        f.write(html_content)

    print("Generated test-report.html from REPORT.md")
