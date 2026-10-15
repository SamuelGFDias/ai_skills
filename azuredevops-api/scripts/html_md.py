#!/usr/bin/env python3
"""Conversor HTML (campos de work item do Azure DevOps) -> Markdown, usado por
export_workitems_helper.py (não é chamado diretamente).

Preserva o que o editor do Azure mostra: listas aninhadas, negrito/itálico, links, imagens,
tabelas e quebras de linha. A numeração é hierárquica por caminho (1. -> 1.1 -> 1.1.1),
independente do `list-style` do Azure (a./i./1.): letras e romanos não ordenam nem se
referenciam bem em texto, o caminho numérico sim. O HTML do Azure costuma ter `<ol>` filho direto de `<ol>` (depois do `</li>`
anterior) — tratado como sublista do item anterior, que é como o Azure renderiza.
"""
import re
from html.parser import HTMLParser

VOID = {"br", "img", "hr", "input", "meta", "link", "col"}
BLOCK = {"p", "div", "blockquote", "ol", "ul", "li", "table", "h1", "h2", "h3", "h4", "h5", "h6",
         "hr", "pre", "tr", "td", "th", "thead", "tbody"}
INDENT = "    "


class Node:
    def __init__(self, tag, attrs=None):
        self.tag, self.attrs, self.children = tag, dict(attrs or {}), []


class _Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("root")
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs)
        self.stack[-1].children.append(n)
        if tag not in VOID:
            self.stack.append(n)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].children.append(Node(tag, attrs))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def _label(path):
    """1. no nível raiz; 1.1, 1.1.1... (item de lista com marcador) nos níveis internos."""
    if len(path) == 1:
        return f"{path[0]}. "
    return "- " + ".".join(map(str, path)) + " "


def _wrap(marker, s):
    core = s.strip()
    if not core:
        return s
    lead = s[: len(s) - len(s.lstrip())]
    trail = s[len(s.rstrip()):]
    return f"{lead}{marker}{core}{marker}{trail}"


class _Renderer:
    def __init__(self, image_map):
        self.image_map = image_map

    # ---- inline: devolve texto com "\n" onde havia <br>
    def inline(self, nodes):
        out = []
        for n in nodes:
            if isinstance(n, str):
                out.append(re.sub(r"[ \t\r\n ]+", " ", n))
                continue
            t = n.tag
            if t == "br":
                out.append("\n")
            elif t == "img":
                src = n.attrs.get("src", "")
                out.append(f"![]({self.image_map.get(src, src)})")
            elif t in ("b", "strong"):
                out.append(_wrap("**", self.inline(n.children)))
            elif t in ("i", "em"):
                out.append(_wrap("*", self.inline(n.children)))
            elif t == "code":
                out.append(_wrap("`", self.inline(n.children)))
            elif t == "a":
                text = self.inline(n.children).strip()
                href = n.attrs.get("href", "")
                out.append(f"[{text or href}]({href})" if href else text)
            elif t in BLOCK:  # bloco dentro de contexto inline (ex.: célula de tabela)
                out.append(" " + self.inline(n.children) + " ")
            else:
                out.append(self.inline(n.children))
        s = "".join(out)
        s = re.sub(r"\*\*(\s*)\*\*", r"\1", s)
        return s

    # ---- blocos: devolve lista de linhas
    def blocks(self, nodes, level, base=()):
        lines, run = [], []

        def flush():
            if not run:
                return
            text = self.inline(run)
            run.clear()
            parts = [p.strip() for p in text.split("\n")]
            while parts and not parts[-1]:
                parts.pop()
            while parts and not parts[0]:
                parts.pop(0)
            for k, p in enumerate(parts):
                if p:
                    lines.append(p + ("  " if k < len(parts) - 1 and parts[k + 1] else ""))

        for n in nodes:
            if isinstance(n, str) or n.tag not in BLOCK:
                run.append(n)
                continue
            flush()
            t = n.tag
            if t in ("ol", "ul"):
                lines += self.list_(n, level, base)
            elif t == "table":
                lines += [""] + self.table(n) + [""]
            elif t == "hr":
                lines += ["", "---", ""]
            elif re.fullmatch(r"h[1-6]", t):
                txt = self.inline(n.children).strip()
                if txt:
                    lines += ["", "#" * int(t[1]) + " " + txt, ""]
            elif t == "li":  # <li> fora de lista: trata como item simples
                lines += self.blocks(n.children, level, base)
            else:  # p, div, blockquote, pre, ...
                lines += self.blocks(n.children, level, base)
        flush()
        return lines

    def list_(self, node, level, base=()):
        count, lines = 0, []
        pad = INDENT * level
        for ch in node.children:
            if isinstance(ch, str):
                continue
            if ch.tag in ("ol", "ul"):  # sublista filha direta da lista (HTML do Azure)
                lines += self.list_(ch, level + 1, base + (count,))
                continue
            if ch.tag != "li":
                continue
            count += 1
            path = base + (count,)
            label = _label(path)
            inner = self.blocks(ch.children, level + 1, path)
            first = True
            for ln in inner:
                if first and not re.match(r"\s*(\d+\. |- )", ln) is None and ln.startswith(INDENT * (level + 1)):
                    # item sem texto próprio: o primeiro conteúdo já é uma sublista
                    lines.append(pad + label.rstrip())
                    first = False
                if first:
                    lines.append(pad + label + ln)
                    first = False
                elif ln.startswith(INDENT * (level + 1)) or ln == "":
                    lines.append(ln)
                else:  # continuação do texto do item (quebra de linha)
                    lines.append(pad + " " * len(label) + ln)
            if first:  # item vazio
                continue
        return lines

    def table(self, node):
        rows = []

        def collect(n):
            for ch in n.children:
                if isinstance(ch, str):
                    continue
                if ch.tag == "tr":
                    rows.append([c for c in ch.children if not isinstance(c, str) and c.tag in ("td", "th")])
                elif ch.tag in ("thead", "tbody", "tfoot"):
                    collect(ch)

        collect(node)
        rows = [r for r in rows if r]
        if not rows:
            return []
        width = max(len(r) for r in rows)

        def cell(c):
            t = self.inline(c.children).strip().replace("|", "\\|")
            return re.sub(r"\s*\n\s*", "<br>", t)

        md = []
        for i, r in enumerate(rows):
            cells = [cell(c) for c in r] + [""] * (width - len(r))
            md.append("| " + " | ".join(cells) + " |")
            if i == 0:
                md.append("|" + "---|" * width)
        return md


def html_to_markdown(raw, image_map=None):
    if not raw or not raw.strip():
        return "(vazio)"
    tree = _Tree()
    tree.feed(raw)
    tree.close()
    lines = _Renderer(image_map or {}).blocks(tree.root.children, 0, ())
    text = "\n".join(lines)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text or "(vazio)"
