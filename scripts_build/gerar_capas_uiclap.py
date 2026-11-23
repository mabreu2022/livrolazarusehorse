#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gerador de Capas Profissionais UICLAP (16 cm x 23 cm) — Trilogia Horse e Lazarus
Autor: Maurício Abreu
Editora: Conect Solutions TI

Gera:
1. Capa Completa Aberta em PDF (Quarta Capa + Lombada + Primeira Capa + 5mm sangria)
2. Capa Aberta em Alta Resolução PNG (300 DPI)
3. Primeira Capa (Front Cover) em Alta Resolução PNG (300 DPI)
"""

import os
import sys
import subprocess
from pathlib import Path
from PIL import Image

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "output" / "capas"
CAPAS_DIR = BASE_DIR / "capas"

CAPAS_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Definição técnica dos 3 volumes no padrão UICLAP
CONFIG_CAPAS = {
    1: {
        "volume": 1,
        "titulo": "Desenvolvimento de APIs REST Modernas com Horse e Lazarus",
        "subtitulo": "Volume 1: Fundamentos do Horse, Roteamento, Middlewares e Segurança JWT",
        "paginas": 111,
        "lombada_mm": 7.0,
        "total_largura_mm": 337.0, # 5 + 160 + 7.0 + 160 + 5
        "altura_mm": 240.0,        # 5 + 230 + 5
        "cor_primaria": "#0284C7",
        "cor_secundaria": "#38BDF8",
        "cor_acento": "#00F0FF",
        "cor_gradiente": "linear-gradient(135deg, #0284C7 0%, #0369A1 50%, #0F172A 100%)",
        "bg_dark": "#070B14",
        "bg_card": "rgba(11, 20, 38, 0.85)",
        "borda_card": "rgba(56, 189, 248, 0.3)",
        "tag_volume": "VOLUME 1 • FUNDAMENTOS, MIDDLEWARES E JWT",
        "destaques": [
            "Arquitetura nativa do Horse sobre fphttpserver no FPC 3.2.2+",
            "Roteamento flexível, verbos HTTP, agrupamento e versionamento de API",
            "Pipeline de Middlewares customizados: Auditoria, Correlation-ID e Rate Limit",
            "Serialização JSON de alta performance com fpjson nativo e Jhonson",
            "Tratamento global de exceções, CORS seguro e padrão RFC 7807",
            "Autenticação stateless com JWT e ciclo de vida de Refresh Tokens no Firebird"
        ],
        "sinopse": (
            "No primeiro volume desta trilogia de engenharia, você aprenderá a construir microsserviços "
            "e APIs REST corporativas de altíssimo desempenho utilizando exclusivamente o ecossistema "
            "moderno do Free Pascal e Lazarus. Esqueça soluções legadas pesadas: explore o poder do "
            "Horse Framework rodando sobre o fphttpserver nativo, processando milhares de requisições por "
            "segundo com consumo irrisório de memória RAM. Do gerenciamento de dependências com Boss CLI "
            "à segurança corporativa com JSON Web Tokens (JWT) e Claims customizadas, este livro entrega "
            "o passo a passo para transformar o Lazarus na sua principal ferramenta de backend moderno."
        ),
        "badges": ["FPC 3.2.2+", "LAZARUS 3.x/5.0", "HORSE FRAMEWORK", "BOSS CLI", "HORSE-JWT", "RFC 7807"]
    },
    2: {
        "volume": 2,
        "titulo": "Desenvolvimento de APIs REST Modernas com Horse e Lazarus",
        "subtitulo": "Volume 2: Arquitetura Limpa, Firebird 5.0 e Persistência de Dados",
        "paginas": 82,
        "lombada_mm": 5.5,
        "total_largura_mm": 335.5, # 5 + 160 + 5.5 + 160 + 5
        "altura_mm": 240.0,        # 5 + 230 + 5
        "cor_primaria": "#EA580C",
        "cor_secundaria": "#F97316",
        "cor_acento": "#FDE047",
        "cor_gradiente": "linear-gradient(135deg, #EA580C 0%, #C2410C 50%, #1C1917 100%)",
        "bg_dark": "#0A0806",
        "bg_card": "rgba(30, 20, 15, 0.85)",
        "borda_card": "rgba(249, 115, 22, 0.3)",
        "tag_volume": "VOLUME 2 • ARQUITETURA LIMPA E FIREBIRD 5.0",
        "destaques": [
            "Clean Architecture, desacoplamento e eliminação de dependências circulares",
            "Contratos rigorosos com Interfaces (IInterface) e injeção de dependência",
            "Modelagem moderna no Firebird 5.0 com colunas IDENTITY, UUIDs e UTF8",
            "O Pool de Conexões Thread-Safe definitivo para SQLdb e ZeosLib",
            "Implementação completa do projeto ConnectOSApi com padrão Unit of Work e DTOs",
            "Paginação de alta velocidade (OFFSET/FETCH) e streaming com horse-octet-stream"
        ],
        "sinopse": (
            "Persistência de dados em alta concorrência exige rigor arquitetural absoluto. No segundo volume, "
            "mergulhe na aplicação prática da Clean Architecture e princípios SOLID em projetos Lazarus, "
            "projetando contratos desacoplados via Interfaces com gerenciamento automático de memória por contagem "
            "de referência. Domine os novos recursos do Firebird 5.0 e resolva o maior desafio de APIs "
            "Lazarus multithread: a construção de um Pool de Conexões Thread-Safe de altíssima resiliência, "
            "garantindo transações ACID atômicas sob carga extrema sem vazamentos de memória ou concorrência indevida."
        ),
        "badges": ["CLEAN ARCHITECTURE", "FIREBIRD 5.0", "POOL THREAD-SAFE", "SQLDB & ZEOS", "UNIT OF WORK", "DTOs"]
    },
    3: {
        "volume": 3,
        "titulo": "Desenvolvimento de APIs REST Modernas com Horse e Lazarus",
        "subtitulo": "Volume 3: Integrações, Qualidade de Software, DevOps e Deploy em Produção",
        "paginas": 66,
        "lombada_mm": 5.0,
        "total_largura_mm": 335.0, # 5 + 160 + 5.0 + 160 + 5
        "altura_mm": 240.0,        # 5 + 230 + 5
        "cor_primaria": "#7C3AED",
        "cor_secundaria": "#A855F7",
        "cor_acento": "#34D399",
        "cor_gradiente": "linear-gradient(135deg, #7C3AED 0%, #6D28D9 50%, #0F0A1A 100%)",
        "bg_dark": "#07040D",
        "bg_card": "rgba(22, 12, 38, 0.85)",
        "borda_card": "rgba(168, 85, 247, 0.3)",
        "tag_volume": "VOLUME 3 • INTEGRAÇÕES, DEVOPS E DEPLOY",
        "destaques": [
            "Consumo de APIs externas com fphttpclient/OpenSSL e Webhooks seguros com HMAC",
            "Documentação viva OpenAPI 3.0 e Swagger UI interativa embarcada no servidor",
            "Testes automatizados com FPCUnit (Mocks, testes de unidade e integração HTTP)",
            "Otimizações de compilação (-O3, smartlinking), HeapTrc e benchmarks com k6/wrk",
            "Transformação em daemons de sistema no Linux (systemd) e serviços Windows nativos",
            "Containerização Docker Multi-Stage (binário < 25MB) e Proxy Reverso Nginx SSL"
        ],
        "sinopse": (
            "Uma API só está verdadeiramente concluída quando opera com robustez, segurança e previsibilidade "
            "em produção. No volume final da trilogia, aprenda a transformar sua aplicação Horse em uma "
            "solução de padrão enterprise: consumo de serviços externos, disparos de webhooks resilientes, "
            "documentação viva com OpenAPI 3.0 embarcada e suíte completa de testes automatizados com FPCUnit "
            "para integração contínua (CI/CD). Culminando na otimização extrema de binários, criação de daemons "
            "nativos systemd no Linux e arquitetura completa de deploy conteinerizado com Docker e Nginx SSL."
        ),
        "badges": ["DOCKER MULTI-STAGE", "NGINX SSL", "SYSTEMD DAEMON", "OPENAPI 3.0", "FPCUNIT CI/CD", "FLAGS -O3"]
    }
}

def get_svg_motif(volume_num, cor_primaria, cor_secundaria, cor_acento):
    """Retorna um diagrama vetorial SVG de alta tecnologia para a capa de cada volume."""
    if volume_num == 1:
        # Pipeline HTTP, nós de rede e Middleware Chain
        return f"""
        <svg viewBox="0 0 400 240" fill="none" xmlns="http://www.w3.org/2000/svg" class="artwork-svg">
            <defs>
                <linearGradient id="netGrad1" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" stop-color="{cor_primaria}" stop-opacity="0.9"/>
                    <stop offset="100%" stop-color="{cor_acento}" stop-opacity="0.9"/>
                </linearGradient>
                <filter id="glow1" x="-20%" y="-20%" width="140%" height="140%">
                    <feGaussianBlur stdDeviation="6" result="blur" />
                    <feComposite in="SourceGraphic" in2="blur" operator="over"/>
                </filter>
            </defs>
            <!-- Malha de Fundo -->
            <path d="M40 120 L120 40 L280 40 L360 120 L280 200 L120 200 Z" stroke="{cor_primaria}" stroke-width="1.5" stroke-dasharray="4 4" opacity="0.4"/>
            <path d="M80 120 L140 60 L260 60 L320 120 L260 180 L140 180 Z" stroke="{cor_secundaria}" stroke-width="1" opacity="0.3"/>
            <!-- Fluxo HTTP Principal -->
            <path d="M20 120 H380" stroke="url(#netGrad1)" stroke-width="3" filter="url(#glow1)"/>
            <!-- Nós do Pipeline -->
            <!-- Client -->
            <circle cx="50" cy="120" r="16" fill="{cor_primaria}" fill-opacity="0.2" stroke="{cor_acento}" stroke-width="2"/>
            <text x="50" y="124" font-family="'JetBrains Mono', monospace" font-size="9" fill="#FFFFFF" text-anchor="middle" font-weight="bold">REQ</text>
            <!-- Middleware 1: CORS -->
            <rect x="105" y="100" width="45" height="40" rx="6" fill="#0B132B" stroke="{cor_secundaria}" stroke-width="1.8"/>
            <text x="127" y="124" font-family="'JetBrains Mono', monospace" font-size="8.5" fill="{cor_secundaria}" text-anchor="middle" font-weight="bold">CORS</text>
            <!-- Middleware 2: JWT -->
            <rect x="175" y="96" width="50" height="48" rx="8" fill="#0B132B" stroke="{cor_acento}" stroke-width="2.2" filter="url(#glow1)"/>
            <text x="200" y="124" font-family="'JetBrains Mono', monospace" font-size="9.5" fill="{cor_acento}" text-anchor="middle" font-weight="bold">JWT</text>
            <!-- Middleware 3: JSON -->
            <rect x="250" y="100" width="45" height="40" rx="6" fill="#0B132B" stroke="{cor_secundaria}" stroke-width="1.8"/>
            <text x="272" y="124" font-family="'JetBrains Mono', monospace" font-size="8.5" fill="{cor_secundaria}" text-anchor="middle" font-weight="bold">JSON</text>
            <!-- Horse Engine Core -->
            <circle cx="340" cy="120" r="22" fill="{cor_primaria}" stroke="#FFFFFF" stroke-width="2.5" filter="url(#glow1)"/>
            <text x="340" y="124" font-family="'JetBrains Mono', monospace" font-size="10" fill="#FFFFFF" text-anchor="middle" font-weight="bold">200</text>
            <!-- Setas e Pulsos -->
            <circle cx="85" cy="120" r="4" fill="{cor_acento}"/>
            <circle cx="160" cy="120" r="4" fill="{cor_acento}"/>
            <circle cx="235" cy="120" r="4" fill="{cor_acento}"/>
            <circle cx="305" cy="120" r="4" fill="{cor_acento}"/>
            <!-- Legenda Inferior -->
            <text x="200" y="225" font-family="'Inter', sans-serif" font-size="9" fill="#94A3B8" text-anchor="middle" letter-spacing="2">PIPELINE DE ALTA PERFORMANCE • HORSE FRAMEWORK</text>
        </svg>
        """
    elif volume_num == 2:
        # Clean Architecture, Camadas Concéntricas e Cilindro Firebird 5.0
        return f"""
        <svg viewBox="0 0 400 240" fill="none" xmlns="http://www.w3.org/2000/svg" class="artwork-svg">
            <defs>
                <linearGradient id="fireGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" stop-color="{cor_primaria}"/>
                    <stop offset="50%" stop-color="{cor_secundaria}"/>
                    <stop offset="100%" stop-color="{cor_acento}"/>
                </linearGradient>
                <filter id="glow2" x="-20%" y="-20%" width="140%" height="140%">
                    <feGaussianBlur stdDeviation="6" result="blur" />
                    <feComposite in="SourceGraphic" in2="blur" operator="over"/>
                </filter>
            </defs>
            <!-- Anéis Concéntricos de Clean Architecture -->
            <circle cx="200" cy="115" r="95" stroke="{cor_primaria}" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.35"/>
            <circle cx="200" cy="115" r="70" stroke="{cor_secundaria}" stroke-width="1.8" opacity="0.55"/>
            <circle cx="200" cy="115" r="45" stroke="{cor_acento}" stroke-width="2.2" opacity="0.8" filter="url(#glow2)"/>
            <!-- Cilindro Firebird 5.0 no Centro -->
            <g transform="translate(165, 85)">
                <ellipse cx="35" cy="12" rx="32" ry="10" fill="{cor_secundaria}" fill-opacity="0.8"/>
                <path d="M3 12 V45 C3 52 17 58 35 58 C53 58 67 52 67 45 V12" fill="{cor_primaria}" fill-opacity="0.8" stroke="{cor_acento}" stroke-width="1.8"/>
                <ellipse cx="35" cy="12" rx="32" ry="10" fill="#1C1917" stroke="{cor_acento}" stroke-width="2"/>
                <ellipse cx="35" cy="30" rx="32" ry="8" stroke="{cor_secundaria}" stroke-width="1" stroke-dasharray="3 3"/>
                <text x="35" y="40" font-family="'JetBrains Mono', monospace" font-size="10" fill="#FFFFFF" text-anchor="middle" font-weight="bold">FB 5.0</text>
            </g>
            <!-- Rótulos de Camadas -->
            <text x="200" y="32" font-family="'JetBrains Mono', monospace" font-size="8.5" fill="{cor_secundaria}" text-anchor="middle" font-weight="600">CONTROLLERS / HTTP API</text>
            <text x="200" y="58" font-family="'JetBrains Mono', monospace" font-size="8" fill="{cor_acento}" text-anchor="middle" font-weight="600">USE CASES / SERVICES</text>
            <text x="200" y="180" font-family="'JetBrains Mono', monospace" font-size="8" fill="{cor_secundaria}" text-anchor="middle" font-weight="600">REPOSITORIES &amp; POOL THREAD-SAFE</text>
            <!-- Orbitas de Entidades -->
            <circle cx="105" cy="115" r="8" fill="{cor_acento}" filter="url(#glow2)"/>
            <text x="105" y="135" font-family="'JetBrains Mono', monospace" font-size="7.5" fill="#FFFFFF" text-anchor="middle">DTO</text>
            <circle cx="295" cy="115" r="8" fill="{cor_secundaria}"/>
            <text x="295" y="135" font-family="'JetBrains Mono', monospace" font-size="7.5" fill="#FFFFFF" text-anchor="middle">DAO</text>
            <!-- Legenda Inferior -->
            <text x="200" y="225" font-family="'Inter', sans-serif" font-size="9" fill="#94A3B8" text-anchor="middle" letter-spacing="2">DOMÍNIO ISOLADO • CONCORRÊNCIA MULTITHREAD ACID</text>
        </svg>
        """
    else:
        # Docker Container Ship, Nginx SSL e CI/CD Pipeline
        return f"""
        <svg viewBox="0 0 400 240" fill="none" xmlns="http://www.w3.org/2000/svg" class="artwork-svg">
            <defs>
                <linearGradient id="prodGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" stop-color="{cor_primaria}"/>
                    <stop offset="50%" stop-color="{cor_secundaria}"/>
                    <stop offset="100%" stop-color="{cor_acento}"/>
                </linearGradient>
                <filter id="glow3" x="-20%" y="-20%" width="140%" height="140%">
                    <feGaussianBlur stdDeviation="6" result="blur" />
                    <feComposite in="SourceGraphic" in2="blur" operator="over"/>
                </filter>
            </defs>
            <!-- Escudo SSL / Nginx -->
            <path d="M90 60 Q130 50 170 60 V120 Q130 160 90 120 Z" fill="#160C26" stroke="{cor_secundaria}" stroke-width="2.2" filter="url(#glow3)"/>
            <text x="130" y="95" font-family="'JetBrains Mono', monospace" font-size="10" fill="#FFFFFF" text-anchor="middle" font-weight="bold">NGINX</text>
            <text x="130" y="112" font-family="'JetBrains Mono', monospace" font-size="8.5" fill="{cor_acento}" text-anchor="middle" font-weight="bold">SSL :443</text>
            <!-- Seta de Encaminhamento -->
            <path d="M175 100 H220" stroke="{cor_acento}" stroke-width="2.5" stroke-dasharray="4 3"/>
            <!-- Bloco Docker Multi-Stage -->
            <g transform="translate(225, 65)">
                <rect x="0" y="0" width="130" height="75" rx="8" fill="#130D21" stroke="{cor_primaria}" stroke-width="2" filter="url(#glow3)"/>
                <!-- Containers Menores -->
                <rect x="10" y="12" width="30" height="20" rx="3" fill="{cor_primaria}" fill-opacity="0.8"/>
                <rect x="48" y="12" width="30" height="20" rx="3" fill="{cor_primaria}" fill-opacity="0.8"/>
                <rect x="86" y="12" width="30" height="20" rx="3" fill="{cor_primaria}" fill-opacity="0.8"/>
                <rect x="28" y="38" width="35" height="22" rx="4" fill="{cor_secundaria}"/>
                <rect x="70" y="38" width="45" height="22" rx="4" fill="{cor_acento}"/>
                <text x="92.5" y="53" font-family="'JetBrains Mono', monospace" font-size="9" fill="#000000" text-anchor="middle" font-weight="bold">HORSE</text>
            </g>
            <!-- Esteira de Pipeline CI/CD FPCUnit -->
            <path d="M50 180 H350" stroke="{cor_secundaria}" stroke-width="1.5" stroke-dasharray="5 5"/>
            <circle cx="80" cy="180" r="10" fill="#130D21" stroke="{cor_acento}" stroke-width="2"/>
            <text x="80" y="183.5" font-family="'JetBrains Mono', monospace" font-size="8" fill="{cor_acento}" text-anchor="middle" font-weight="bold">BUILD</text>
            <circle cx="180" cy="180" r="10" fill="#130D21" stroke="{cor_acento}" stroke-width="2"/>
            <text x="180" y="183.5" font-family="'JetBrains Mono', monospace" font-size="8" fill="{cor_acento}" text-anchor="middle" font-weight="bold">TEST</text>
            <circle cx="280" cy="180" r="10" fill="#130D21" stroke="{cor_acento}" stroke-width="2"/>
            <text x="280" y="183.5" font-family="'JetBrains Mono', monospace" font-size="8" fill="{cor_acento}" text-anchor="middle" font-weight="bold">DEPLOY</text>
            <!-- Legenda Inferior -->
            <text x="200" y="225" font-family="'Inter', sans-serif" font-size="9" fill="#94A3B8" text-anchor="middle" letter-spacing="2">DOCKER MULTI-STAGE • SYSTEMD • NGINX REVERSE PROXY</text>
        </svg>
        """

def generate_cover_html(vol_cfg):
    """Gera o HTML editorial completo da capa aberta com medidas estritas UICLAP."""
    v = vol_cfg["volume"]
    total_w = vol_cfg["total_largura_mm"]
    spine_w = vol_cfg["lombada_mm"]
    cor_prim = vol_cfg["cor_primaria"]
    cor_sec = vol_cfg["cor_secundaria"]
    cor_acento = vol_cfg["cor_acento"]
    cor_primaria = cor_prim
    cor_secundaria = cor_sec
    bg_dark = vol_cfg["bg_dark"]
    bg_card = vol_cfg["bg_card"]
    borda_card = vol_cfg["borda_card"]
    
    svg_art = get_svg_motif(v, cor_prim, cor_sec, cor_acento)
    
    badges_html = "".join([f'<span class="badge">{b}</span>' for b in vol_cfg["badges"]])
    destaques_html = "".join([f'<li><span class="bullet" style="color:{cor_acento};">▸</span> {d}</li>' for d in vol_cfg["destaques"]])
    
    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>Capa Completa Volume {v} — UICLAP (16 cm x 23 cm)</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600;700&family=Space+Grotesk:wght@600;700&display=swap');
        
        @page {{
            size: {total_w}mm 240mm;
            margin: 0;
        }}
        
        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }}
        
        body {{
            width: {total_w}mm;
            height: 240mm;
            background-color: {bg_dark};
            font-family: 'Inter', -apple-system, sans-serif;
            color: #F8FAFC;
            overflow: hidden;
            position: relative;
        }}
        
        /* Grade de Fundo Tecnológica Sutis */
        .grid-overlay {{
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background-image: 
                linear-gradient(to right, rgba(255, 255, 255, 0.03) 1px, transparent 1px),
                linear-gradient(to bottom, rgba(255, 255, 255, 0.03) 1px, transparent 1px);
            background-size: 20mm 20mm;
            pointer-events: none;
            z-index: 1;
        }}
        
        /* Container Principal da Capa Aberta */
        .cover-spread {{
            display: flex;
            width: {total_w}mm;
            height: 240mm;
            position: relative;
            z-index: 2;
        }}
        
        /* 1. QUARTA CAPA (Contracapa / Back Cover) = 5mm sangria + 160mm */
        .back-cover {{
            width: 165mm; /* 5mm sangria esquerda + 160mm */
            height: 240mm;
            padding-top: 15mm;
            padding-bottom: 15mm;
            padding-left: 20mm; /* 5mm sangria + 15mm margem segura */
            padding-right: 15mm;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            position: relative;
            border-right: 1px dashed rgba(255, 255, 255, 0.08); /* Linha de vinco da lombada */
        }}
        
        /* 2. LOMBADA (Spine) */
        .spine {{
            width: {spine_w}mm;
            height: 240mm;
            background: linear-gradient(180deg, {cor_prim} 0%, rgba(15, 23, 42, 0.95) 20%, rgba(15, 23, 42, 0.95) 80%, {cor_prim} 100%);
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: space-between;
            padding: 12mm 0;
            position: relative;
            border-left: 1px dashed rgba(255, 255, 255, 0.15);
            border-right: 1px dashed rgba(255, 255, 255, 0.15);
        }}
        
        .spine-text {{
            writing-mode: vertical-rl;
            transform: rotate(180deg);
            font-family: 'Space Grotesk', 'Inter', sans-serif;
            font-size: 7.5pt;
            font-weight: 700;
            letter-spacing: 0.12em;
            color: #F8FAFC;
            white-space: nowrap;
            text-transform: uppercase;
        }}
        
        .spine-badge {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 7pt;
            font-weight: 800;
            color: {cor_acento};
            background: rgba(0, 0, 0, 0.6);
            padding: 3px 2px;
            border-radius: 3px;
            border: 1px solid {cor_acento};
            text-align: center;
            width: 90%;
        }}
        
        /* 3. PRIMEIRA CAPA (Front Cover) = 160mm + 5mm sangria */
        .front-cover {{
            width: 165mm; /* 160mm + 5mm sangria direita */
            height: 240mm;
            padding-top: 15mm;
            padding-bottom: 15mm;
            padding-left: 15mm;
            padding-right: 20mm; /* 15mm margem segura + 5mm sangria */
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            position: relative;
            background: radial-gradient(circle at 85% 20%, rgba({int(cor_prim[1:3], 16)}, {int(cor_prim[3:5], 16)}, {int(cor_prim[5:7], 16)}, 0.25) 0%, transparent 60%);
        }}
        
        /* Elementos da Frente */
        .series-tag {{
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid {borda_card};
            padding: 4px 10px;
            border-radius: 4px;
            font-family: 'Space Grotesk', sans-serif;
            font-size: 7.5pt;
            font-weight: 700;
            letter-spacing: 0.15em;
            color: {cor_acento};
            text-transform: uppercase;
            width: fit-content;
        }}
        
        .title-block {{
            margin-top: 10mm;
        }}
        
        .title-lead {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 11pt;
            font-weight: 600;
            letter-spacing: 0.12em;
            color: #94A3B8;
            text-transform: uppercase;
            margin-bottom: 2mm;
        }}
        
        .title-main {{
            font-family: 'Space Grotesk', 'Inter', sans-serif;
            font-size: 21pt;
            font-weight: 900;
            line-height: 1.15;
            color: #FFFFFF;
            text-transform: uppercase;
            letter-spacing: -0.02em;
        }}
        
        .title-accent {{
            color: {cor_secundaria};
            display: block;
            margin-top: 1.5mm;
            text-shadow: 0 0 25px rgba({int(cor_prim[1:3], 16)}, {int(cor_prim[3:5], 16)}, {int(cor_prim[5:7], 16)}, 0.6);
        }}
        
        .volume-card {{
            background: {bg_card};
            border-left: 3.5px solid {cor_acento};
            border-top: 1px solid {borda_card};
            border-right: 1px solid {borda_card};
            border-bottom: 1px solid {borda_card};
            padding: 8px 12px;
            border-radius: 4px;
            margin-top: 5mm;
            backdrop-filter: blur(8px);
        }}
        
        .volume-card-title {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 8.5pt;
            font-weight: 700;
            color: {cor_acento};
            letter-spacing: 0.08em;
            text-transform: uppercase;
        }}
        
        .volume-card-desc {{
            font-size: 8pt;
            color: #CBD5E1;
            margin-top: 2px;
            line-height: 1.35;
        }}
        
        .artwork-container {{
            width: 100%;
            height: 52mm;
            margin: 4mm 0;
            display: flex;
            align-items: center;
            justify-content: center;
        }}
        
        .artwork-svg {{
            width: 100%;
            max-height: 100%;
        }}
        
        .tech-badges-grid {{
            display: flex;
            flex-wrap: wrap;
            gap: 4px;
            margin-bottom: 4mm;
        }}
        
        .badge {{
            background: rgba(15, 23, 42, 0.7);
            border: 1px solid rgba(255, 255, 255, 0.12);
            color: #E2E8F0;
            font-family: 'JetBrains Mono', monospace;
            font-size: 6.5pt;
            font-weight: 600;
            padding: 2.5px 6px;
            border-radius: 3px;
        }}
        
        .author-footer {{
            border-top: 1px solid rgba(255, 255, 255, 0.12);
            padding-top: 3.5mm;
            display: flex;
            align-items: flex-end;
            justify-content: space-between;
        }}
        
        .author-name {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 14pt;
            font-weight: 800;
            color: #FFFFFF;
            letter-spacing: 0.02em;
        }}
        
        .author-role {{
            font-size: 7.5pt;
            color: #94A3B8;
            margin-top: 1px;
        }}
        
        .publisher-label {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 6.5pt;
            color: {cor_secundaria};
            text-align: right;
            font-weight: 600;
        }}
        
        /* Estilos da Quarta Capa */
        .back-header {{
            border-bottom: 2px solid {cor_prim};
            padding-bottom: 3mm;
            margin-bottom: 4mm;
        }}
        
        .back-title {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 11pt;
            font-weight: 800;
            color: #FFFFFF;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            line-height: 1.25;
        }}
        
        .back-synopsis {{
            font-size: 7.8pt;
            color: #CBD5E1;
            line-height: 1.45;
            text-align: justify;
            margin-bottom: 4mm;
        }}
        
        .back-highlights-box {{
            background: {bg_card};
            border: 1px solid {borda_card};
            border-radius: 5px;
            padding: 8px 10px;
            margin-bottom: 4mm;
        }}
        
        .back-highlights-title {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 8pt;
            font-weight: 700;
            color: {cor_acento};
            text-transform: uppercase;
            letter-spacing: 0.06em;
            margin-bottom: 4px;
        }}
        
        .back-highlights-list {{
            list-style: none;
        }}
        
        .back-highlights-list li {{
            font-size: 7.2pt;
            color: #E2E8F0;
            line-height: 1.35;
            margin-bottom: 2.5px;
            display: flex;
            align-items: flex-start;
            gap: 5px;
        }}
        
        .bullet {{
            font-weight: bold;
        }}
        
        .back-author-box {{
            display: flex;
            gap: 10px;
            align-items: center;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
            padding-top: 3mm;
            margin-bottom: 4mm;
        }}
        
        .author-bio {{
            font-size: 7.2pt;
            color: #94A3B8;
            line-height: 1.35;
            text-align: justify;
        }}
        
        .back-footer {{
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding-top: 3mm;
            border-top: 1px solid rgba(255, 255, 255, 0.12);
        }}
        
        .barcode-box {{
            width: 50mm;
            height: 28mm;
            background-color: #FFFFFF;
            border-radius: 3px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 3px;
            box-shadow: 0 4px 10px rgba(0, 0, 0, 0.4);
        }}
        
        .barcode-mock {{
            width: 90%;
            height: 18mm;
            background: repeating-linear-gradient(
                to right,
                #000 0px, #000 2px,
                #fff 2px, #fff 4px,
                #000 4px, #000 7px,
                #fff 7px, #fff 8px,
                #000 8px, #000 11px,
                #fff 11px, #fff 14px,
                #000 14px, #000 15px,
                #fff 15px, #fff 18px,
                #000 18px, #000 22px
            );
        }}
        
        .barcode-label {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 5pt;
            color: #1E293B;
            font-weight: bold;
            margin-top: 2px;
            letter-spacing: 0.05em;
        }}
        
        .back-brand-info {{
            display: flex;
            flex-direction: column;
            gap: 2px;
        }}
        
        .brand-logo-text {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 9pt;
            font-weight: 800;
            color: #FFFFFF;
            letter-spacing: 0.05em;
        }}
        
        .brand-subtext {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 6.5pt;
            color: {cor_secundaria};
        }}
    </style>
</head>
<body>
    <div class="grid-overlay"></div>
    
    <div class="cover-spread">
        <!-- ========================================== -->
        <!-- 1. QUARTA CAPA (CONTRACAPA / BACK COVER)   -->
        <!-- ========================================== -->
        <div class="back-cover">
            <div>
                <div class="back-header">
                    <div style="font-family:'Space Grotesk',sans-serif; font-size:7pt; color:{cor_acento}; font-weight:700; letter-spacing:0.15em; text-transform:uppercase; margin-bottom:2px;">TRILOGIA HORSE &amp; LAZARUS • VOL. {v}</div>
                    <h2 class="back-title">Engenharia de Produção Nativamente em Pascal</h2>
                </div>
                
                <p class="back-synopsis">{vol_cfg["sinopse"]}</p>
                
                <div class="back-highlights-box">
                    <div class="back-highlights-title">O Que Você Vai Dominar Neste Volume</div>
                    <ul class="back-highlights-list">
                        {destaques_html}
                    </ul>
                </div>
                
                <div class="back-author-box">
                    <div class="author-bio">
                        <strong style="color:#FFFFFF;">Maurício Abreu</strong> é Arquiteto de Software, Especialista em Object Pascal (Lazarus / Delphi) e fundador da <strong style="color:{cor_acento};">Conect Solutions TI</strong>. Atua há mais de uma década no desenvolvimento de microsserviços de missão crítica, telecomunicações e arquiteturas distribuídas de alta performance.
                    </div>
                </div>
            </div>
            
            <div class="back-footer">
                <div class="back-brand-info">
                    <div class="brand-logo-text">CONECT SOLUTIONS TI</div>
                    <div class="brand-subtext">PUBLICAÇÕES TÉCNICAS DE ENGENHARIA</div>
                    <div style="font-size:6pt; color:#64748B; margin-top:2px;">FORMATO FÍSICO UICLAP 160 × 230 mm</div>
                </div>
                
                <!-- Área do Código de Barras / ISBN Exigido pela UICLAP -->
                <div class="barcode-box">
                    <div class="barcode-mock"></div>
                    <div class="barcode-label">UICLAP • ISBN &amp; DEPÓSITO LEGAL</div>
                </div>
            </div>
        </div>
        
        <!-- ========================================== -->
        <!-- 2. LOMBADA (SPINE)                         -->
        <!-- ========================================== -->
        <div class="spine">
            <div class="spine-badge">V.{v}</div>
            <div class="spine-text">MAURÍCIO ABREU &nbsp;•&nbsp; HORSE E LAZARUS &nbsp;•&nbsp; VOL. {v}</div>
            <div style="font-family:'Space Grotesk',sans-serif; font-size:6pt; font-weight:800; color:#FFFFFF; text-align:center;">CSTI</div>
        </div>
        
        <!-- ========================================== -->
        <!-- 3. PRIMEIRA CAPA (FRONT COVER)             -->
        <!-- ========================================== -->
        <div class="front-cover">
            <div>
                <div class="series-tag">
                    <span style="display:inline-block; width:6px; height:6px; border-radius:50%; background-color:{cor_acento};"></span>
                    {vol_cfg["tag_volume"]}
                </div>
                
                <div class="title-block">
                    <div class="title-lead">DESENVOLVIMENTO DE</div>
                    <h1 class="title-main">APIS REST<br>MODERNAS</h1>
                    <div class="title-main title-accent">COM HORSE &amp; LAZARUS</div>
                </div>
                
                <div class="volume-card">
                    <div class="volume-card-title">{vol_cfg["subtitulo"].split(':')[1].strip() if ':' in vol_cfg["subtitulo"] else vol_cfg["subtitulo"]}</div>
                    <div class="volume-card-desc">Da fundamentação de rede ao ciclo de vida completo de engenharia em produção</div>
                </div>
            </div>
            
            <div class="artwork-container">
                {svg_art}
            </div>
            
            <div>
                <div class="tech-badges-grid">
                    {badges_html}
                </div>
                
                <div class="author-footer">
                    <div>
                        <div class="author-name">Maurício Abreu</div>
                        <div class="author-role">Arquiteto de Software • Conect Solutions TI</div>
                    </div>
                    <div class="publisher-label">
                        EDIÇÃO DEFINITIVA<br>PADRÃO UICLAP 16×23
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"""
    return html

def generate_front_cover_html(vol_cfg):
    """Gera o HTML isolado apenas da Primeira Capa (160mm x 230mm + 5mm sangria = 170mm x 240mm) para visualização e catálogo."""
    v = vol_cfg["volume"]
    cor_prim = vol_cfg["cor_primaria"]
    cor_sec = vol_cfg["cor_secundaria"]
    cor_acento = vol_cfg["cor_acento"]
    cor_primaria = cor_prim
    cor_secundaria = cor_sec
    bg_dark = vol_cfg["bg_dark"]
    bg_card = vol_cfg["bg_card"]
    borda_card = vol_cfg["borda_card"]
    
    svg_art = get_svg_motif(v, cor_prim, cor_sec, cor_acento)
    badges_html = "".join([f'<span class="badge">{b}</span>' for b in vol_cfg["badges"]])
    
    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>Primeira Capa Volume {v} — Maurício Abreu</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600;700&family=Space+Grotesk:wght@600;700&display=swap');
        
        @page {{
            size: 170mm 240mm;
            margin: 0;
        }}
        
        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }}
        
        body {{
            width: 170mm;
            height: 240mm;
            background-color: {bg_dark};
            font-family: 'Inter', -apple-system, sans-serif;
            color: #F8FAFC;
            overflow: hidden;
            position: relative;
            padding: 15mm 18mm;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            background: radial-gradient(circle at 85% 20%, rgba({int(cor_prim[1:3], 16)}, {int(cor_prim[3:5], 16)}, {int(cor_prim[5:7], 16)}, 0.3) 0%, transparent 60%);
        }}
        
        .grid-overlay {{
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background-image: 
                linear-gradient(to right, rgba(255, 255, 255, 0.03) 1px, transparent 1px),
                linear-gradient(to bottom, rgba(255, 255, 255, 0.03) 1px, transparent 1px);
            background-size: 20mm 20mm;
            pointer-events: none;
            z-index: 1;
        }}
        
        .content {{
            position: relative;
            z-index: 2;
            height: 100%;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
        }}
        
        .series-tag {{
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid {borda_card};
            padding: 4px 10px;
            border-radius: 4px;
            font-family: 'Space Grotesk', sans-serif;
            font-size: 8pt;
            font-weight: 700;
            letter-spacing: 0.15em;
            color: {cor_acento};
            text-transform: uppercase;
            width: fit-content;
        }}
        
        .title-block {{
            margin-top: 8mm;
        }}
        
        .title-lead {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 11pt;
            font-weight: 600;
            letter-spacing: 0.12em;
            color: #94A3B8;
            text-transform: uppercase;
            margin-bottom: 2mm;
        }}
        
        .title-main {{
            font-family: 'Space Grotesk', 'Inter', sans-serif;
            font-size: 22pt;
            font-weight: 900;
            line-height: 1.15;
            color: #FFFFFF;
            text-transform: uppercase;
            letter-spacing: -0.02em;
        }}
        
        .title-accent {{
            color: {cor_secundaria};
            display: block;
            margin-top: 1.5mm;
            text-shadow: 0 0 25px rgba({int(cor_prim[1:3], 16)}, {int(cor_prim[3:5], 16)}, {int(cor_prim[5:7], 16)}, 0.6);
        }}
        
        .volume-card {{
            background: {bg_card};
            border-left: 3.5px solid {cor_acento};
            border-top: 1px solid {borda_card};
            border-right: 1px solid {borda_card};
            border-bottom: 1px solid {borda_card};
            padding: 8px 12px;
            border-radius: 4px;
            margin-top: 5mm;
            backdrop-filter: blur(8px);
        }}
        
        .volume-card-title {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 9pt;
            font-weight: 700;
            color: {cor_acento};
            letter-spacing: 0.08em;
            text-transform: uppercase;
        }}
        
        .volume-card-desc {{
            font-size: 8pt;
            color: #CBD5E1;
            margin-top: 2px;
            line-height: 1.35;
        }}
        
        .artwork-container {{
            width: 100%;
            height: 52mm;
            margin: 4mm 0;
            display: flex;
            align-items: center;
            justify-content: center;
        }}
        
        .artwork-svg {{
            width: 100%;
            max-height: 100%;
        }}
        
        .tech-badges-grid {{
            display: flex;
            flex-wrap: wrap;
            gap: 4px;
            margin-bottom: 4mm;
        }}
        
        .badge {{
            background: rgba(15, 23, 42, 0.7);
            border: 1px solid rgba(255, 255, 255, 0.12);
            color: #E2E8F0;
            font-family: 'JetBrains Mono', monospace;
            font-size: 6.8pt;
            font-weight: 600;
            padding: 2.5px 6px;
            border-radius: 3px;
        }}
        
        .author-footer {{
            border-top: 1px solid rgba(255, 255, 255, 0.12);
            padding-top: 3.5mm;
            display: flex;
            align-items: flex-end;
            justify-content: space-between;
        }}
        
        .author-name {{
            font-family: 'Space Grotesk', sans-serif;
            font-size: 14pt;
            font-weight: 800;
            color: #FFFFFF;
            letter-spacing: 0.02em;
        }}
        
        .author-role {{
            font-size: 7.5pt;
            color: #94A3B8;
            margin-top: 1px;
        }}
        
        .publisher-label {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 6.5pt;
            color: {cor_secundaria};
            text-align: right;
            font-weight: 600;
        }}
    </style>
</head>
<body>
    <div class="grid-overlay"></div>
    <div class="content">
        <div>
            <div class="series-tag">
                <span style="display:inline-block; width:6px; height:6px; border-radius:50%; background-color:{cor_acento};"></span>
                {vol_cfg["tag_volume"]}
            </div>
            
            <div class="title-block">
                <div class="title-lead">DESENVOLVIMENTO DE</div>
                <h1 class="title-main">APIS REST<br>MODERNAS</h1>
                <div class="title-main title-accent">COM HORSE &amp; LAZARUS</div>
            </div>
            
            <div class="volume-card">
                <div class="volume-card-title">{vol_cfg["subtitulo"].split(':')[1].strip() if ':' in vol_cfg["subtitulo"] else vol_cfg["subtitulo"]}</div>
                <div class="volume-card-desc">Da fundamentação de rede ao ciclo de vida completo de engenharia em produção</div>
            </div>
        </div>
        
        <div class="artwork-container">
            {svg_art}
        </div>
        
        <div>
            <div class="tech-badges-grid">
                {badges_html}
            </div>
            
            <div class="author-footer">
                <div>
                    <div class="author-name">Maurício Abreu</div>
                    <div class="author-role">Arquiteto de Software • Conect Solutions TI</div>
                </div>
                <div class="publisher-label">
                    EDIÇÃO DEFINITIVA<br>PADRÃO UICLAP 16×23
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"""
    return html

def find_chrome():
    paths = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    ]
    for p in paths:
        if os.path.exists(p):
            return p
    return None

def render_covers_volume(vol_num):
    chrome_bin = find_chrome()
    if not chrome_bin:
        print("[ERRO] Chrome ou Edge nao encontrado.")
        sys.exit(1)
        
    cfg = CONFIG_CAPAS[vol_num]
    print(f"\n=======================================================")
    print(f" GERANDO CAPA UICLAP — VOLUME {vol_num}")
    print(f" Subtitulo: {cfg['subtitulo']}")
    print(f" Lombada:   {cfg['lombada_mm']} mm (para {cfg['paginas']} paginas)")
    print(f" Largura:   {cfg['total_largura_mm']} mm x Altura: {cfg['altura_mm']} mm")
    print(f"=======================================================")
    
    # 1. Gerar e salvar HTML da Capa Aberta
    html_aberta = generate_cover_html(cfg)
    html_aberta_path = CAPAS_DIR / f"capa_volume_{vol_num}_aberta.html"
    with open(html_aberta_path, "w", encoding="utf-8") as f:
        f.write(html_aberta)
        
    # 2. Gerar e salvar HTML da Primeira Capa
    html_frente = generate_front_cover_html(cfg)
    html_frente_path = CAPAS_DIR / f"capa_volume_{vol_num}_frente.html"
    with open(html_frente_path, "w", encoding="utf-8") as f:
        f.write(html_frente)
        
    # 3. Compilar PDF da Capa Completa Aberta (Padrão UICLAP)
    pdf_output_path = OUTPUT_DIR / f"Capa_Completa_Volume_{vol_num}_UICLAP.pdf"
    cmd_pdf = [
        chrome_bin,
        "--headless=new",
        "--disable-gpu",
        "--run-all-compositor-stages-before-draw",
        "--print-to-pdf-no-header",
        f"--print-to-pdf={pdf_output_path}",
        str(html_aberta_path)
    ]
    subprocess.run(cmd_pdf, check=True)
    size_pdf_kb = os.path.getsize(pdf_output_path) / 1024
    print(f" [✓] PDF Aberto UICLAP: {pdf_output_path.name} ({size_pdf_kb:.1f} KB)")
    
    # 4. Renderizar PNG de Alta Resolução da Capa Aberta (300 DPI: ~3980x2835 px)
    # 1 mm ≈ 11.81 pixels a 300 DPI
    px_w = int(cfg["total_largura_mm"] * 11.811)
    px_h = int(cfg["altura_mm"] * 11.811)
    
    png_aberta_path = OUTPUT_DIR / f"Capa_Aberta_Volume_{vol_num}.png"
    cmd_png_aberta = [
        chrome_bin,
        "--headless=new",
        "--disable-gpu",
        f"--window-size={px_w},{px_h}",
        f"--screenshot={png_aberta_path}",
        str(html_aberta_path)
    ]
    subprocess.run(cmd_png_aberta, check=True)
    size_png_aberta_kb = os.path.getsize(png_aberta_path) / 1024
    print(f" [✓] PNG Capa Aberta:  {png_aberta_path.name} ({px_w}x{px_h} px | {size_png_aberta_kb:.1f} KB)")
    
    # 5. Renderizar PNG de Alta Resolução da Primeira Capa (Front Cover)
    # 170mm x 240mm (com sangria) a 300 DPI = ~2008x2835 px
    px_front_w = int(170 * 11.811)
    px_front_h = int(240 * 11.811)
    png_frente_path = OUTPUT_DIR / f"Capa_Frente_Volume_{vol_num}.png"
    cmd_png_frente = [
        chrome_bin,
        "--headless=new",
        "--disable-gpu",
        f"--window-size={px_front_w},{px_front_h}",
        f"--screenshot={png_frente_path}",
        str(html_frente_path)
    ]
    subprocess.run(cmd_png_frente, check=True)
    size_png_frente_kb = os.path.getsize(png_frente_path) / 1024
    print(f" [✓] PNG Primeira Capa: {png_frente_path.name} ({px_front_w}x{px_front_h} px | {size_png_frente_kb:.1f} KB)")

def main():
    print("=======================================================")
    print(" PIPELINE DE GERAÇÃO DE CAPAS UICLAP (16 cm x 23 cm)  ")
    print(" Obra: Desenvolvimento de APIs REST Modernas com Horse")
    print(" Autor: Maurício Abreu                                 ")
    print(" Formato: 3 Volumes Independentes com Lombada Ajustada ")
    print("=======================================================")
    
    for v in [1, 2, 3]:
        render_covers_volume(v)
        
    print("\n=======================================================")
    print(" TODAS AS 3 CAPAS UICLAP FORAM GERADAS COM SUCESSO!   ")
    print(f" Diretório de saída: {OUTPUT_DIR}")
    print("=======================================================\n")

if __name__ == "__main__":
    main()
