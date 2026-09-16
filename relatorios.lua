-- relatorios.lua
-- Gerador de Relatorios Analiticos, Logs de Telemetria (CSV) e Benchmarks de Desenvolvimento

local M = {}

-- Formata numeros com separador de milhar (ex: 1,500,000)
local function formatarNumero(n)
    if not n then return "0" end
    local formatado = string.format("%.0f", n)
    local k
    while true do
        formatado, k = string.gsub(formatado, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatado
end

-- Gera timestamp seguro mesmo em ambientes CC sem os.date completo
local function obterTimestamp()
    if os.date then
        local ok, data = pcall(os.date, "%Y-%m-%d %H:%M:%S")
        if ok and data then return data end
    end
    return string.format("Dia %d, %s", os.day and os.day() or 0, textutils and textutils.formatTime(os.time(), true) or tostring(os.time()))
end

local function obterNomeArquivoSeguro()
    if os.date then
        local ok, data = pcall(os.date, "%Y%m%d_%H%M%S")
        if ok and data then return "relatorio_" .. data .. ".txt" end
    end
    return string.format("relatorio_d%s_t%s.txt", tostring(os.day and os.day() or 0), tostring(math.floor(os.time() * 100)))
end

-- 1. GERADOR DE RELATORIO ANALITICO EM TEXTO (.txt)
function M.gerarRelatorioTexto(dados, pastaDestino)
    pastaDestino = pastaDestino or "relatorios/"
    if fs and not fs.exists(pastaDestino) then
        pcall(fs.makeDir, pastaDestino)
    end

    local r = dados.reator
    local turbinas = dados.turbinas or {}
    local dataStr = obterTimestamp()
    local nomeArquivo = obterNomeArquivoSeguro()
    local caminhoCompleto = pastaDestino .. nomeArquivo

    local linhas = {}
    local function add(l) table.insert(linhas, l or "") end

    add("================================================================================")
    add("            RELATORIO DE DESEMPENHO E EFICIENCIA - EXTREME REACTORS              ")
    add("================================================================================")
    add(string.format(" Data da Coleta:     %s", dataStr))
    add(string.format(" Modo do Sistema:    %s", dados.modo or "DESCONHECIDO"))
    add(string.format(" Perfil de Operacao: %s (%s)", dados.perfil or "EFICIENCIA", (dados.perfil == "POTENCIA") and "MAXIMA POTENCIA" or "ECO EFICIENCIA"))
    add(string.format(" Status Operacional: %s", dados.estado or "DESCONHECIDO"))
    add(string.format(" Alerta / Mensagem:  %s", dados.alerta or "Nenhum"))
    add("--------------------------------------------------------------------------------")
    add(" 1. METRICAS GERAIS DE EFICIENCIA")
    add("--------------------------------------------------------------------------------")
    add(string.format("  Eficiencia Global:        %s RF / mB de Combustivel", formatarNumero(dados.eficiencia_rf_mb)))
    
    if r then
        local energiaRF = r.energia_tick or 0
        local queimaMB = r.consumo_tick or 0
        local queimaMinuto = queimaMB * 20 * 60
        add(string.format("  Geracao Direta Reator:    %s RF/t", formatarNumero(energiaRF)))
        add(string.format("  Taxa de Queima:           %.4f mB/t  (~%.2f mB por minuto)", queimaMB, queimaMinuto))
        add(string.format("  Nivel Medio das Barras:   %d%% (Alvo do Algoritmo: %d%%)", r.barras_nivel or 0, dados.barras_alvo or 0))
    end

    add("--------------------------------------------------------------------------------")
    add(" 2. NUCLEO DO REATOR (CONDICOES TERMICAS E MATERIAIS)")
    add("--------------------------------------------------------------------------------")
    if r then
        add(string.format("  Temp. do Combustivel:     %.1f C  (Faixa Ideal: 550 C - 750 C)", r.temp_combustivel or 0))
        add(string.format("  Temp. da Carcaca:         %.1f C", r.temp_carcaca or 0))
        add(string.format("  Combustivel Armazenado:   %s / %s mB (%.1f%%)",
            formatarNumero(r.combustivel_armazenado), formatarNumero(r.combustivel_max), r.combustivel_pct or 0))
        add(string.format("  Residuo Acumulado (Lixo): %s mB", formatarNumero(r.lixo_armazenado)))
        add(string.format("  Reatividade Nuclear:      %.1f%%", r.reatividade or 0))
        add(string.format("  Buffer de Energia:        %s / %s RF (%.1f%%)",
            formatarNumero(r.energia_armazenada), formatarNumero(r.energia_capacidade), r.energia_pct or 0))

        if r.ativo_refrigerado then
            add(string.format("  Tanque Refrigerante:      %s / %s mB (Agua)", formatarNumero(r.agua), formatarNumero(r.agua_max)))
            add(string.format("  Tanque Vapor (Vapor):     %s / %s mB | Producao: %s mB/t",
                formatarNumero(r.vapor), formatarNumero(r.vapor_max), formatarNumero(r.vapor_tick)))
        end
    else
        add("  [!] Nenhum Reator Conectado.")
    end

    add("--------------------------------------------------------------------------------")
    add(" 3. TURBINAS E GERADORES DE VAPOR (" .. tostring(#turbinas) .. " CONECTADAS)")
    add("--------------------------------------------------------------------------------")
    if #turbinas > 0 then
        local somaRFTurbinas = 0
        local somaVazaoTurbinas = 0
        for i, t in ipairs(turbinas) do
            somaRFTurbinas = somaRFTurbinas + (t.energia_tick or 0)
            somaVazaoTurbinas = somaVazaoTurbinas + (t.vazao_max or 0)
            local deltaRPM = (t.rpm or 0) - 1800
            local sinal = deltaRPM >= 0 and "+" or ""
            local statusRpm = (math.abs(deltaRPM) <= 15) and "[OTIMO: 100% EFICIENCIA]" or "[AJUSTANDO FLUXO]"
            
            add(string.format("  [Turbina #%d - %s]", i, t.nome or "Turbina"))
            add(string.format("    Rotacao:                %.1f RPM (%s%.1f RPM do Ponto Doce) %s", t.rpm or 0, sinal, deltaRPM, statusRpm))
            add(string.format("    Indutor / Bobina:       %s", t.indutor and "ENGAJADO (GERANDO ENERGIA)" or "LIVRE (EM ACELERACAO)"))
            add(string.format("    Vazao de Vapor:         %s mB/t (Consumo Real: %s mB/t)", formatarNumero(t.vazao_max), formatarNumero(t.vazao_atual)))
            add(string.format("    Eficiencia das Pas:     %.1f%%", t.eficiencia_pas or 0))
            add(string.format("    Energia Produzida:      %s RF/t", formatarNumero(t.energia_tick)))
        end
        add("  ------------------------------------------------------------------------------")
        add(string.format("  TOTAL TURBINAS: %s RF/t  |  DEMANDA TOTAL DE VAPOR: %s mB/t",
            formatarNumero(somaRFTurbinas), formatarNumero(somaVazaoTurbinas)))
    else
        add("  [Nenhuma turbina detectada. Sistema operando em modo de geracao passiva direta]")
    end

    add("--------------------------------------------------------------------------------")
    add(" 4. DIAGNOSTICO E DICAS DE DESENVOLVIMENTO / ENGENHARIA")
    add("--------------------------------------------------------------------------------")
    local avisos = 0
    if r then
        if (r.temp_combustivel or 0) > 850 then
            avisos = avisos + 1
            add(string.format("  [DICA-TERMICA] Temp. do combustivel elevada (%.1f C). O consumo cresce", r.temp_combustivel))
            add("                 exponencialmente acima de 800 C. Considere refrigeracao criogenica ou elevar as barras.")
        end
        if (r.energia_pct or 0) > 90 then
            avisos = avisos + 1
            add("  [DICA-ENERGIA] Buffer de RF quase cheio (>90%). O sistema reduziu a queima para evitar perdas.")
        end
        if r.ativo_refrigerado and #turbinas > 0 then
            local vaporGerado = r.vapor_tick or 0
            local somaVazao = 0
            for _, t in ipairs(turbinas) do somaVazao = somaVazao + (t.vazao_max or 0) end
            if vaporGerado < somaVazao * 0.9 then
                avisos = avisos + 1
                add(string.format("  [DICA-VAPOR] Producao de vapor (%d mB/t) inferior a demanda das turbinas (%d mB/t).", vaporGerado, somaVazao))
                add("               As turbinas podem sofrer queda de RPM. Aumente as barras ou expanda o reator.")
            end
        end
    end
    if avisos == 0 then
        add("  [EXCELENTE] O sistema esta operando em parametros otimizados de maxima eficiencia.")
    end

    add("================================================================================")
    add("                  FIM DO RELATORIO - GERADO VIA CC: TWEAKED                     ")
    add("================================================================================")

    local conteudo = table.concat(linhas, "\n")

    if fs then
        local arq = fs.open(caminhoCompleto, "w")
        if arq then
            arq.write(conteudo)
            arq.close()
            return true, caminhoCompleto, conteudo
        end
    end

    return false, caminhoCompleto, conteudo
end

-- 2. REGISTRADOR DE TELEMETRIA CONTÍNUA EM CSV
function M.registrarLinhaCSV(dados, arquivoCSV)
    arquivoCSV = arquivoCSV or "relatorios/telemetria.csv"
    if not fs then return false end

    -- Se o arquivo nao existe, cria com cabecalho
    if not fs.exists(arquivoCSV) then
        local cabecalho = "Timestamp,Modo,Estado,RF_Total_Tick,Consumo_Combustivel_mBt,Eficiencia_RF_mB,Temp_Combustivel_C,Temp_Carcaca_C,Energia_Buffer_Pct,Barras_Nivel_Pct,Turbinas_Qtd,Turbina1_RPM,Turbina1_RFt\n"
        local arq = fs.open(arquivoCSV, "w")
        if arq then
            arq.write(cabecalho)
            arq.close()
        end
    end

    local r = dados.reator
    local turbinas = dados.turbinas or {}
    local dataStr = obterTimestamp()

    local rfTotal = 0
    if r then rfTotal = rfTotal + (r.energia_tick or 0) end
    for _, t in ipairs(turbinas) do rfTotal = rfTotal + (t.energia_tick or 0) end

    local turb1Rpm = (#turbinas > 0) and turbinas[1].rpm or 0
    local turb1RF = (#turbinas > 0) and turbinas[1].energia_tick or 0

    local linha = string.format("%s,%s,%s,%d,%.4f,%d,%.1f,%.1f,%.1f,%d,%d,%.1f,%d\n",
        dataStr,
        dados.modo or "N/A",
        dados.estado or "N/A",
        rfTotal,
        (r and r.consumo_tick) or 0,
        dados.eficiencia_rf_mb or 0,
        (r and r.temp_combustivel) or 0,
        (r and r.temp_carcaca) or 0,
        (r and r.energia_pct) or 0,
        (r and r.barras_nivel) or 0,
        #turbinas,
        turb1Rpm,
        turb1RF
    )

    local arq = fs.open(arquivoCSV, "a")
    if arq then
        arq.write(linha)
        arq.close()
        return true
    end
    return false
end

-- 3. BENCHMARK E CURVA DE EFICIENCIA
function M.executarBenchmark(controlador, cbProgresso)
    local r = controlador.peri.reator
    if not r then
        return nil, "Reator nao disponivel para benchmark."
    end

    local estadoOriginal = controlador.estado
    controlador.estado = controlador.ESTADOS.CALIBRANDO

    local niveis = { 0, 20, 40, 60, 80 }
    local resultados = {}

    -- Garante que o reator esta ligado
    r.setAtivo(true)

    for idx, nivel in ipairs(niveis) do
        r.setBarras(nivel)
        if cbProgresso then
            cbProgresso(string.format("Testando barras em %d%% (%d/%d)... Aguardando estabilizacao", nivel, idx, #niveis))
        end

        -- Aguarda estabilizacao termica (aproximadamente 6 segundos no jogo)
        if os.sleep then
            for _ = 1, 6 do
                os.sleep(1)
            end
        end

        -- Coleta dados medios
        local temp = r.tempCombustivel()
        local rf = r.energiaProduzidaTick()
        local consumo = r.consumoCombustivelTick()
        local vapor = r.vaporProduzidoTick()
        local eff = (consumo > 0.00001) and (rf / consumo) or 0

        table.insert(resultados, {
            nivel_barras = nivel,
            temperatura = temp,
            energia_rf_t = rf,
            vapor_mb_t = vapor,
            consumo_mb_t = consumo,
            eficiencia_rf_mb = math.floor(eff)
        })
    end

    -- Restaura estado
    controlador.estado = estadoOriginal
    controlador:determinarModo()

    -- Encontra o melhor patamar de eficiencia e o de melhor potencia
    local melhorEff = resultados[1]
    local melhorPot = resultados[1]
    for _, res in ipairs(resultados) do
        if res.eficiencia_rf_mb > (melhorEff.eficiencia_rf_mb or 0) then
            melhorEff = res
        end
        local valPotAtual = (res.energia_rf_t and res.energia_rf_t > 0) and res.energia_rf_t or (res.vapor_mb_t or 0)
        local valPotMelhor = (melhorPot.energia_rf_t and melhorPot.energia_rf_t > 0) and melhorPot.energia_rf_t or (melhorPot.vapor_mb_t or 0)
        if valPotAtual > valPotMelhor then
            melhorPot = res
        end
    end

    -- Salva relatorio de benchmark em arquivo
    local dataStr = obterTimestamp()
    local nomeBenchmark = "relatorios/benchmark_" .. (os.date and os.date("%Y%m%d_%H%M%S") or "resultado") .. ".txt"
    local linhasBench = {
        "================================================================================",
        "            RESULTADO DO BENCHMARK DA CURVA DE RENDIMENTO                       ",
        "================================================================================",
        string.format(" Data do Teste: %s", dataStr),
        "",
        string.format(" %-12s | %-12s | %-14s | %-14s | %-16s", "Barras (%)", "Temp (C)", "Geracao (RF/t)", "Queima (mB/t)", "Eficiencia (RF/mB)"),
        "--------------------------------------------------------------------------------",
    }

    for _, res in ipairs(resultados) do
        table.insert(linhasBench, string.format(" %-12d | %-12.1f | %-14s | %-14.4f | %-16s",
            res.nivel_barras, res.temperatura, formatarNumero(res.energia_rf_t), res.consumo_mb_t, formatarNumero(res.eficiencia_rf_mb)))
    end

    table.insert(linhasBench, "--------------------------------------------------------------------------------")
    table.insert(linhasBench, string.format(" [★] MELHOR POTENCIA BRUTA:    Barras em %d%% (Gera %s RF/t | %s mB/t vapor)",
        melhorPot.nivel_barras, formatarNumero(melhorPot.energia_rf_t), formatarNumero(melhorPot.vapor_mb_t)))
    table.insert(linhasBench, string.format(" [★] MELHOR EFICIENCIA (ECO):  Barras em %d%% (%s RF/mB de combustivel)",
        melhorEff.nivel_barras, formatarNumero(melhorEff.eficiencia_rf_mb)))
    table.insert(linhasBench, "================================================================================")

    local relatorioFinal = table.concat(linhasBench, "\n")
    if fs then
        local arq = fs.open(nomeBenchmark, "w")
        if arq then
            arq.write(relatorioFinal)
            arq.close()
        end
    end

    return resultados, nomeBenchmark, relatorioFinal
end

return M
