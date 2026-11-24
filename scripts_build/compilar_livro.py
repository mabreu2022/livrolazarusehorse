#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script de Compilação Editorial — Trilogia UICLAP (16 cm x 23 cm)
Livro: Desenvolvimento de APIs REST Modernas com Horse e Lazarus
Autor: Maurício Abreu
Divisão em 3 Volumes de ~333 páginas para atendimento estrito ao limite UICLAP
"""

import os
import re
import sys
import argparse
import subprocess
from pathlib import Path
import pypdf

BASE_DIR = Path(__file__).resolve().parent.parent
CAPITULOS_DIR = BASE_DIR / "capitulos"
OUTPUT_DIR = BASE_DIR / "output"
SCRIPTS_DIR = BASE_DIR / "scripts_build"
CSS_FILE = SCRIPTS_DIR / "estilo_uiclap_16x23.css"

VOLUMES_CONFIG = {
    0: {
        "numero": 0,
        "titulo": "Desenvolvimento de APIs REST Modernas com Horse e Lazarus",
        "subtitulo": "Edição Completa Consolidada (20 Módulos)",
        "output_pdf": "Livro_Horse_Lazarus_Volume_Unico.pdf",
        "output_html": "livro_volume_unico.html",
        "capitulos": [
            "00_pre_textuais.md",
            "01_anatomia_http_horse_fpc.md",
            "02_setup_lazarus_boss_primeiro_servidor.md",
            "03_roteamento_avancado_verbos_parametros.md",
            "04_requisicoes_respostas_status_http.md",
            "05_pipeline_middlewares_next.md",
            "06_serializacao_json_fpjson_jhonson.md",
            "07_cors_tratamento_global_excecoes.md",
            "08_autenticacao_jwt_refresh_tokens.md",
            "09_arquitetura_limpa_mvc_interfaces_lazarus.md",
            "10_modelagem_firebird5_identity_utf8.md",
            "11_pool_conexoes_thread_safe_firebird.md",
            "12_crud_completo_transacoes_dto.md",
            "13_paginacao_filtros_dinamicos_performance.md",
            "14_upload_download_arquivos_octetstream.md",
            "15_consumo_apis_externas_webhooks.md",
            "16_documentacao_openapi_swagger.md",
            "17_testes_automatizados_fpcunit.md",
            "18_otimizacao_compilacao_cruzada_linux.md",
            "19_servicos_daemon_systemd_windows_service.md",
            "20_nginx_proxy_reverso_ssl_docker.md",
            "21_pos_textuais.md"
        ]
    },
    1: {
        "numero": 1,
        "titulo": "Desenvolvimento de APIs REST Modernas com Horse e Lazarus",
        "subtitulo": "Volume 1: Fundamentos do Horse, Roteamento, Middlewares e Segurança JWT",
        "output_pdf": "Livro_Horse_Lazarus_Volume_1.pdf",
        "output_html": "livro_volume_1.html",
        "capitulos": [
            "00_pre_textuais_vol1.md",
            "01_anatomia_http_horse_fpc.md",
            "02_setup_lazarus_boss_primeiro_servidor.md",
            "03_roteamento_avancado_verbos_parametros.md",
            "04_requisicoes_respostas_status_http.md",
            "05_pipeline_middlewares_next.md",
            "06_serializacao_json_fpjson_jhonson.md",
            "07_cors_tratamento_global_excecoes.md",
            "08_autenticacao_jwt_refresh_tokens.md",
            "21_pos_textuais_vol1.md"
        ]
    },
    2: {
        "numero": 2,
        "titulo": "Desenvolvimento de APIs REST Modernas com Horse e Lazarus",
        "subtitulo": "Volume 2: Arquitetura Limpa, Firebird 5.0 e Persistência de Dados",
        "output_pdf": "Livro_Horse_Lazarus_Volume_2.pdf",
        "output_html": "livro_volume_2.html",
        "capitulos": [
            "00_pre_textuais_vol2.md",
            "09_arquitetura_limpa_mvc_interfaces_lazarus.md",
            "10_modelagem_firebird5_identity_utf8.md",
            "11_pool_conexoes_thread_safe_firebird.md",
            "12_crud_completo_transacoes_dto.md",
            "13_paginacao_filtros_dinamicos_performance.md",
            "14_upload_download_arquivos_octetstream.md",
            "21_pos_textuais_vol2.md"
        ]
    },
    3: {
        "numero": 3,
        "titulo": "Desenvolvimento de APIs REST Modernas com Horse e Lazarus",
        "subtitulo": "Volume 3: Integrações, Qualidade de Software, DevOps e Deploy em Produção",
        "output_pdf": "Livro_Horse_Lazarus_Volume_3.pdf",
        "output_html": "livro_volume_3.html",
        "capitulos": [
            "00_pre_textuais_vol3.md",
            "15_consumo_apis_externas_webhooks.md",
            "16_documentacao_openapi_swagger.md",
            "17_testes_automatizados_fpcunit.md",
            "18_otimizacao_compilacao_cruzada_linux.md",
            "19_servicos_daemon_systemd_windows_service.md",
            "20_nginx_proxy_reverso_ssl_docker.md",
            "21_pos_textuais_vol3.md"
        ]
    }
}

def check_dependencies():
    """Garante que markdown e pypdf estejam disponíveis."""
    try:
        import markdown
    except ImportError:
        print("[!] Instalando dependencia Python: markdown...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "markdown", "pygments", "pypdf"])

def preprocess_markdown(cap_files):
    """Unifica e formata arquivos Markdown do volume."""
    full_content = []
    
    for filename in cap_files:
        fpath = CAPITULOS_DIR / filename
        if not fpath.exists():
            print(f"[ERRO] Arquivo nao encontrado: {fpath}")
            sys.exit(1)
            
        with open(fpath, "r", encoding="utf-8") as f:
            content = f.read()
            
        # Remove \newpage que antecede h1 (que ja quebra pagina automaticamente)
        content = re.sub(r'\\newpage\s*(?:\n\s*<!--.*?-->\s*)*\n\s*(?=#[^#])', '\n\n', content)
        content = re.sub(r'\\newpage', '<div class="newpage"></div>', content)
        content = re.sub(r'\\vspace\*?\{[^}]*\}', '<div style="margin: 20px 0;"></div>', content)
        
        full_content.append(content)
        
    return "\n\n".join(full_content)

def build_html(markdown_text, vol_cfg):
    """Converte Markdown para HTML completo com suporte a CSS UICLAP."""
    import markdown
    
    extensions = [
        'extra',
        'tables',
        'fenced_code',
        'toc',
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
    <title>{vol_cfg['titulo']} — {vol_cfg['subtitulo']} — Maurício Abreu</title>
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
    html_output_path = OUTPUT_DIR / vol_cfg['output_html']
    with open(html_output_path, "w", encoding="utf-8") as f:
        f.write(html_doc)
        
    return html_output_path

def find_pdf_renderer():
    """Identifica o Chrome ou Edge disponivel."""
    chrome_paths = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    ]
    for p in chrome_paths:
        if os.path.exists(p):
            return ("browser", p)
            
    return (None, None)

def render_volume_pdf(html_path, vol_cfg):
    """Compila o PDF do volume e reporta a contagem de páginas exata."""
    engine_type, engine_bin = find_pdf_renderer()
    pdf_output_path = OUTPUT_DIR / vol_cfg['output_pdf']
    
    if not engine_type:
        print("[ERRO] Navegador Chrome/Edge nao localizado para renderizar PDF.")
        return False
        
    print(f"[*] Compilando {vol_cfg['subtitulo']} via {os.path.basename(engine_bin)}...")
    cmd = [
        engine_bin,
        "--headless=new",
        "--disable-gpu",
        "--run-all-compositor-stages-before-draw",
        "--print-to-pdf-no-header",
        f"--print-to-pdf={pdf_output_path}",
        str(html_path)
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if res.returncode == 0 and pdf_output_path.exists():
        reader = pypdf.PdfReader(str(pdf_output_path))
        num_paginas = len(reader.pages)
        size_kb = os.path.getsize(pdf_output_path) / 1024
        print(f"[SUCESSO] Volume {vol_cfg['numero']} gerado!")
        print(f"          Arquivo:  {pdf_output_path.name}")
        print(f"          Paginas:  {num_paginas} paginas")
        print(f"          Tamanho:  {size_kb:.1f} KB")
        return num_paginas
    else:
        print(f"[ERRO] Falha ao compilar Volume {vol_cfg['numero']}: {res.stderr.decode('utf-8', errors='ignore')}")
        return False

def compilar_volume(vol_num):
    """Compila um volume especifico."""
    vol_cfg = VOLUMES_CONFIG[vol_num]
    print(f"\n=================================================================")
    print(f" COMPILANDO: {vol_cfg['subtitulo']}")
    print(f"=================================================================")
    raw_md = preprocess_markdown(vol_cfg['capitulos'])
    html_file = build_html(raw_md, vol_cfg)
    return render_volume_pdf(html_file, vol_cfg)

def main():
    parser = argparse.ArgumentParser(description="Compilador Editorial UICLAP (3 Volumes ou Volume Único)")
    parser.add_argument("--volume", type=int, choices=[0, 1, 2, 3], help="Numero do volume a compilar (1, 2, 3 para Trilogia ou 0 para Volume Unico)")
    args = parser.parse_args()
    
    check_dependencies()
    
    print("=================================================================")
    print(" PIPELINE EDITORIAL DA TRILOGIA UICLAP (16 cm x 23 cm)           ")
    print(" Livro: Desenvolvimento de APIs REST Modernas com Horse e Lazarus")
    print(" Autor: Maurício Abreu                                           ")
    print("=================================================================")
    
    volumes_to_build = [args.volume] if args.volume is not None else [1, 2, 3]
    resultados = {}
    
    for v in volumes_to_build:
        paginas = compilar_volume(v)
        resultados[v] = paginas
        
    print("\n=================================================================")
    print(" RESUMO FINAL DA TRILOGIA UICLAP")
    print("=================================================================")
    for v, p in resultados.items():
        cfg = VOLUMES_CONFIG[v]
        status_uiclap = "OK (<= 999 pags)" if p and p <= 999 else "EXCEDE LIMITE"
        print(f" * Volume {v}: {p} paginas | {cfg['output_pdf']} [{status_uiclap}]")
    print("=================================================================\n")

if __name__ == "__main__":
    main()
