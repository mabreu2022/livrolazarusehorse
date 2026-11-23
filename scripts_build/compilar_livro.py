#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script de Compilação Editorial — Livro Técnico UICLAP (16 cm x 23 cm)
Livro: Desenvolvimento de APIs REST Modernas com Horse e Lazarus
Autor: Maurício Abreu
"""

import os
import re
import sys
import glob
import subprocess
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
CAPITULOS_DIR = BASE_DIR / "capitulos"
OUTPUT_DIR = BASE_DIR / "output"
SCRIPTS_DIR = BASE_DIR / "scripts_build"
CSS_FILE = SCRIPTS_DIR / "estilo_uiclap_16x23.css"
PDF_OUTPUT = OUTPUT_DIR / "Livro_Horse_Lazarus_Mauricio_Abreu_16x23.pdf"
HTML_OUTPUT = OUTPUT_DIR / "livro_completo.html"

def check_dependencies():
    """Verifica e importa módulos necessários."""
    try:
        import markdown
    except ImportError:
        print("[!] Instalando dependencia Python: markdown...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "markdown", "pygments"])

def collect_chapters():
    """Coleta e ordena todos os arquivos markdown da pasta capitulos/."""
    pattern = str(CAPITULOS_DIR / "*.md")
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"[ERRO] Nenhum arquivo .md encontrado em {CAPITULOS_DIR}")
        sys.exit(1)
    print(f"[*] Encontrados {len(files)} capitulo(s):")
    for f in files:
        print(f"    - {os.path.basename(f)}")
    return files

def preprocess_markdown(md_files):
    """Unifica e limpa os arquivos Markdown para renderizacao."""
    full_content = []
    
    for fpath in md_files:
        with open(fpath, "r", encoding="utf-8") as f:
            content = f.read()
            
        # Substitui comandos LaTeX comuns por tags HTML compativeis
        content = re.sub(r'\\newpage', '<div class="newpage"></div>', content)
        content = re.sub(r'\\vspace\*?\{[^}]*\}', '<div style="margin: 20px 0;"></div>', content)
        
        # Converte caixas de alerta em classes estilizadas
        content = content.replace('> **Nota de Arquitetura:**', '<blockquote class="alert-arquitetura"><strong>Nota de Arquitetura:</strong>')
        content = content.replace('> **Atenção Thread-Safety:**', '<blockquote class="alert-threadsafety"><strong>Atenção Thread-Safety:</strong>')
        content = content.replace('> **Boas Práticas FPC:**', '<blockquote class="alert-fpc"><strong>Boas Práticas FPC:</strong>')
        
        full_content.append(content)
        full_content.append('\n\n<div class="newpage"></div>\n\n')
        
    return "\n".join(full_content)

def build_html(markdown_text):
    """Converte Markdown para HTML completo com suporte a TOC e CSS UICLAP."""
    import markdown
    
    extensions = [
        'extra',
        'tables',
        'fenced_code',
        'toc',
        'nl2br',
        'sane_lists'
    ]
    
    md_parser = markdown.Markdown(extensions=extensions)
    html_body = md_parser.convert(markdown_text)
    
    css_content = ""
    if CSS_FILE.exists():
        with open(CSS_FILE, "r", encoding="utf-8") as f:
            css_content = f.read()
            
    html_doc = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Desenvolvimento de APIs REST Modernas com Horse e Lazarus - Maurício Abreu</title>
    <style>
{css_content}
    </style>
</head>
<body>
<div class="book-container">
{html_body}
</div>
</body>
</html>
"""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(HTML_OUTPUT, "w", encoding="utf-8") as f:
        f.write(html_doc)
        
    print(f"[OK] Documento HTML intermediario gerado: {HTML_OUTPUT}")
    return HTML_OUTPUT

def find_pdf_renderer():
    """Identifica o motor de renderizacao de PDF disponivel."""
    # 1. Tentar Chrome no Windows
    chrome_paths = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    ]
    for p in chrome_paths:
        if os.path.exists(p):
            return ("browser", p)
            
    # 2. Tentar comando weasyprint
    try:
        res = subprocess.run(["weasyprint", "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0:
            return ("weasyprint", "weasyprint")
    except Exception:
        pass
        
    return (None, None)

def render_pdf(html_path):
    """Gera o PDF final utilizando o renderizador disponivel."""
    engine_type, engine_bin = find_pdf_renderer()
    
    if not engine_type:
        print("[AVISO] Nenhum renderizador PDF (Chrome/Edge/WeasyPrint) encontrado no PATH.")
        print(f"[INFO] O arquivo HTML completo foi gerado com sucesso em: {html_path}")
        print("Voce pode abri-lo no navegador e salvar como PDF em formato 160mm x 230mm.")
        return False
        
    print(f"[*] Compilando PDF via {engine_type} ({os.path.basename(engine_bin)})...")
    
    if engine_type == "browser":
        # Usando Edge ou Chrome em modo headless com margens de corte e impressao de background
        cmd = [
            engine_bin,
            "--headless=new",
            "--disable-gpu",
            "--run-all-compositor-stages-before-draw",
            "--print-to-pdf-no-header",
            f"--print-to-pdf={PDF_OUTPUT}",
            str(html_path)
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0 and PDF_OUTPUT.exists():
            size_kb = os.path.getsize(PDF_OUTPUT) / 1024
            print(f"[SUCESSO] PDF gerado: {PDF_OUTPUT} ({size_kb:.1f} KB)")
            return True
        else:
            print(f"[ERRO] Falha na execucao do browser: {res.stderr.decode('utf-8', errors='ignore')}")
            return False
            
    elif engine_type == "weasyprint":
        cmd = ["weasyprint", str(html_path), str(PDF_OUTPUT)]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0 and PDF_OUTPUT.exists():
            size_kb = os.path.getsize(PDF_OUTPUT) / 1024
            print(f"[SUCESSO] PDF gerado via WeasyPrint: {PDF_OUTPUT} ({size_kb:.1f} KB)")
            return True
            
    return False

def main():
    print("=================================================================")
    print(" PIPELINE DE COMPILACAO EDITORIAL — PADRAO UICLAP 16 cm x 23 cm  ")
    print(" Livro: Desenvolvimento de APIs REST Modernas com Horse e Lazarus")
    print(" Autor: Maurício Abreu                                           ")
    print("=================================================================")
    
    check_dependencies()
    md_files = collect_chapters()
    raw_md = preprocess_markdown(md_files)
    html_file = build_html(raw_md)
    render_pdf(html_file)
    print("=================================================================")
    print(" Processo de compilacao finalizado.")
    print("=================================================================")

if __name__ == "__main__":
    main()
