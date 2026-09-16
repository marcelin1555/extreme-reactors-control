-- controlador.lua
-- Nucleo logico de controle de alta eficiencia para Extreme Reactors e Turbinas

local M = {}

-- Estados possiveis
M.ESTADOS = {
    OPERANDO = "OPERANDO",
    STANDBY = "STANDBY",
    EMERGENCIA = "SCRAM (EMERGENCIA)",
    CALIBRANDO = "CALIBRANDO",
    MANUAL = "MANUAL",
}

function M.novo(cfg, perifericos)
    local c = {
        ESTADOS = M.ESTADOS,
        cfg = cfg,
        peri = perifericos,
        estado = M.ESTADOS.STANDBY,
        modo = "DESCONHECIDO", -- "PASSIVO" ou "ATIVO_TURBINA"
        scram_manual = false,
        motivo_alerta = "Sistema iniciado",
        
        -- Estatisticas e telemetria
        stats = {
            tempo_operacao = 0,
            eficiencia_media_rf_mb = 0,
            consumo_total_mb = 0,
            energia_total_rf = 0,
            vapor_total_mb = 0,
            barras_alvo = 50,
            turbinas_sincronizadas = 0,
            dados_recentes = {}
        }
    }

    -- Determina o modo de operacao automaticamente ou forca config
    function c:determinarModo()
        local modoCfg = self.cfg.ativo.modo_operacao
        if modoCfg == "passivo" then
            self.modo = "PASSIVO"
        elseif modoCfg == "ativo" then
            self.modo = "ATIVO_TURBINA"
        else
            -- Modo auto
            local r = self.peri.reator
            local temTurbinas = (#self.peri.turbinas > 0)
            if temTurbinas or (r and r.isAtivoRefrigerado()) then
                self.modo = "ATIVO_TURBINA"
            else
                self.modo = "PASSIVO"
            end
        end
    end

    -- Dispara desligamento de emergencia
    function c:acionarScram(motivo)
        self.estado = M.ESTADOS.EMERGENCIA
        self.motivo_alerta = motivo or "SCRAM Acionado!"
        if self.peri.reator then
            self.peri.reator.setBarras(100)
            self.peri.reator.setAtivo(false)
        end
        for _, t in ipairs(self.peri.turbinas) do
            t.setIndutor(false)
            t.setVazao(0)
        end
    end

    -- Cancela o scram caso as condicoes estejam seguras
    function c:limparScram()
        self.scram_manual = false
        self.estado = M.ESTADOS.STANDBY
        self.motivo_alerta = "SCRAM redefinido. Sistema em espera."
    end

    -- Alterna SCRAM Manual pelo teclado/usuario
    function c:alternarScramManual()
        self.scram_manual = not self.scram_manual
        if self.scram_manual then
            self:acionarScram("SCRAM manual acionado pelo operador")
        else
            self:limparScram()
        end
    end

    -- Loop de controle para Modo Passivo (Somente Reator)
    function c:processarPassivo()
        local r = self.peri.reator
        if not r then return end

        local cfgR = self.cfg.ativo.reator
        local tempComb = r.tempCombustivel()
        local bufferPct = r.energiaPorcentagem()
        local energiaRF = r.energiaProduzidaTick()
        local consumoMB = r.consumoCombustivelTick()

        -- 1. Verificacao de Seguranca Termica
        if tempComb >= cfgR.temp_scram then
            self:acionarScram(string.format("Temperatura critica no nucleo: %.1f C", tempComb))
            return
        end

        -- 2. Logica de Descarte de Lixo (Cianita)
        if cfgR.auto_ejetar_lixo and r.lixoArmazenado() > 1000 then
            r.ejetarLixo()
        end

        -- 3. Decisao de Ligado/Desligado (Histerese de Buffer)
        if bufferPct >= cfgR.buffer_energia_max then
            -- Buffer muito cheio: desliga ou barras em 100% para parar de queimar combustivel a toa
            r.setBarras(100)
            if bufferPct >= 96 then
                r.setAtivo(false)
            end
            self.estado = M.ESTADOS.STANDBY
            self.motivo_alerta = string.format("Buffer cheio (%.1f%%). Economizando combustivel.", bufferPct)
            self.stats.barras_alvo = 100
            return
        end

        if bufferPct <= cfgR.buffer_energia_min then
            -- Buffer baixo: liga reator se estiver desligado
            if not r.ativo() then
                r.setAtivo(true)
            end
            self.estado = M.ESTADOS.OPERANDO
        end

        -- Se estiver em standby mas abaixo do maximo, reativa suavemente
        if not r.ativo() and bufferPct < (cfgR.buffer_energia_max - 5) then
            r.setAtivo(true)
            self.estado = M.ESTADOS.OPERANDO
        end

        -- 4. Modulacao Dinamica das Barras para Maxima Eficiencia
        -- Mapeia a insercao das barras proporcionalmente ao estado da carga (20% -> 0% barras, 85% -> 90% barras)
        local span = math.max(1, cfgR.buffer_energia_max - cfgR.buffer_energia_min)
        local fatorCarga = (bufferPct - cfgR.buffer_energia_min) / span
        fatorCarga = math.max(0, math.min(1, fatorCarga))

        -- Nivel base derivado do buffer de energia
        local nivelBase = fatorCarga * 85

        -- Correcao termica: se o combustivel esquentar alem do alvo (650 C),
        -- o consumo de uranio dispara sem aumentar proporcionalmente a energia.
        -- Adiciona freio termico suave.
        local excessoTermico = math.max(0, tempComb - cfgR.temp_alvo_combustivel)
        local freioTermico = (excessoTermico / 20) * 1.5

        local nivelFinal = math.min(99, math.max(0, math.floor(nivelBase + freioTermico)))

        -- Aplica o novo nivel de barras
        r.setBarras(nivelFinal)
        self.stats.barras_alvo = nivelFinal

        -- Atualiza calculo de eficiencia instantanea (RF por mB de combustivel)
        if consumoMB > 0.00001 then
            local eff = energiaRF / consumoMB
            if self.stats.eficiencia_media_rf_mb == 0 then
                self.stats.eficiencia_media_rf_mb = eff
            else
                -- Media movel exponencial
                self.stats.eficiencia_media_rf_mb = (self.stats.eficiencia_media_rf_mb * 0.9) + (eff * 0.1)
            end
        end

        self.motivo_alerta = string.format("Modulando barras: %d%% | Temp: %.1f C | Buffer: %.1f%%",
            nivelFinal, tempComb, bufferPct)
    end

    -- Loop de controle para Modo Ativo + Turbinas
    function c:processarAtivoComTurbinas()
        local r = self.peri.reator
        local turbinas = self.peri.turbinas
        local cfgT = self.cfg.ativo.turbina
        local cfgR = self.cfg.ativo.reator

        if not r then return end

        local tempComb = r.tempCombustivel()
        local liqRefrig = r.liquidoRefrigerante()
        local liqMax = r.liquidoRefrigeranteMax()
        local liqPct = (liqMax > 0) and (liqRefrig / liqMax * 100) or 100

        -- 1. Seguranca: SCRAM por superaquecimento ou falta critica de agua
        if tempComb >= cfgR.temp_scram then
            self:acionarScram(string.format("Temperatura critica no nucleo: %.1f C", tempComb))
            return
        end
        if r.isAtivoRefrigerado() and liqPct < 8 then
            self:acionarScram("Agua de refrigeracao esgotada! Risco de fusao seca.")
            return
        end

        -- Garante que o reator esta ligado
        if not r.ativo() then
            r.setAtivo(true)
        end

        local demandaVaporTotal = 0
        local turbinasOk = 0

        -- 2. Controle Individual de Cada Turbina (Foco: 1800 RPM exatos)
        for _, t in ipairs(turbinas) do
            if not t.ativo() then t.setAtivo(true) end
            t.respiro(cfgT.modo_respiro)

            local rpm = t.rpm()
            local indutor = t.indutorAtivo()
            local vazaoAtual = t.vazaoMax()
            local tetoVazao = math.min(cfgT.vazao_max_limite, t.vazaoTeto())

            -- Logica de Partida e Giro Livre:
            -- Enquanto estiver abaixo da rotacao de engate, desliga o indutor para cortar
            -- o atrito magnetico e acelerar em segundos.
            if rpm < cfgT.rpm_engajar_indutor then
                if indutor then
                    t.setIndutor(false)
                end
                -- Abre fluxo para acelerar
                t.setVazao(tetoVazao)
            else
                -- Turbina atingiu a faixa ideal (~1800 RPM)
                if not indutor then
                    t.setIndutor(true)
                end

                -- Ajuste Fino de Fluxo de Vapor (Manutencao dos 1800 RPM)
                if rpm > (cfgT.rpm_alvo + cfgT.rpm_tolerancia) then
                    -- Rotação subindo alem do sweet spot -> diminui vapor
                    local novaVazao = math.max(50, vazaoAtual - cfgT.passo_vazao)
                    t.setVazao(novaVazao)
                elseif rpm < (cfgT.rpm_alvo - cfgT.rpm_tolerancia) then
                    -- Rotação caindo -> aumenta vapor
                    local novaVazao = math.min(tetoVazao, vazaoAtual + cfgT.passo_vazao)
                    t.setVazao(novaVazao)
                else
                    -- Exatamente no ponto doce (1800 RPM +/- tolerancia)
                    turbinasOk = turbinasOk + 1
                end
            end

            demandaVaporTotal = demandaVaporTotal + t.vazaoMax()
        end

        self.stats.turbinas_sincronizadas = turbinasOk

        -- 3. Balanceamento do Reator Ativo para Gerar o Vapor Exato
        -- Compara a producao atual de vapor com a demanda total das turbinas
        local vaporGerado = r.vaporProduzidoTick()
        local nivelVaporTanque = (r.vaporMax() > 0) and (r.vaporArmazenado() / r.vaporMax() * 100) or 50
        local nivelBarras = r.getNivelBarras()

        if demandaVaporTotal <= 0 then
            demandaVaporTotal = 2000 -- Fallback se turbina estiver vazia
        end

        -- Se o tanque de vapor do reator estiver estufando (>80%), insere barras
        if nivelVaporTanque > 80 then
            local novoNivel = math.min(100, nivelBarras + 3)
            r.setBarras(novoNivel)
            self.stats.barras_alvo = novoNivel
        -- Se o vapor produzido for menor que a demanda, recua as barras para ferver mais agua
        elseif vaporGerado < (demandaVaporTotal * 0.95) then
            local novoNivel = math.max(0, nivelBarras - 1)
            r.setBarras(novoNivel)
            self.stats.barras_alvo = novoNivel
        -- Se estiver produzindo vapor em excesso alem da demanda das turbinas, sobe barras
        elseif vaporGerado > (demandaVaporTotal * 1.05) then
            local novoNivel = math.min(99, nivelBarras + 1)
            r.setBarras(novoNivel)
            self.stats.barras_alvo = novoNivel
        end

        -- 4. Eficiencia Global
        local consumoMB = r.consumoCombustivelTick()
        local energiaTotalTurbinas = 0
        for _, t in ipairs(turbinas) do
            energiaTotalTurbinas = energiaTotalTurbinas + t.energiaProduzidaTick()
        end

        if consumoMB > 0.00001 then
            local eff = energiaTotalTurbinas / consumoMB
            if self.stats.eficiencia_media_rf_mb == 0 then
                self.stats.eficiencia_media_rf_mb = eff
            else
                self.stats.eficiencia_media_rf_mb = (self.stats.eficiencia_media_rf_mb * 0.9) + (eff * 0.1)
            end
        end

        self.estado = M.ESTADOS.OPERANDO
        self.motivo_alerta = string.format("Turbinas a 1800 RPM: %d/%d | Demanda Vapor: %d mB/t | Reator: %d mB/t",
            turbinasOk, #turbinas, demandaVaporTotal, vaporGerado)
    end

    -- Ciclo principal chamado periodicamente
    function c:atualizar()
        if not self.peri.reator then
            self.estado = M.ESTADOS.STANDBY
            self.motivo_alerta = "Aguardando conexao do reator..."
            return
        end

        if self.scram_manual or self.estado == M.ESTADOS.EMERGENCIA then
            -- Permanece parado ate limpeza de erro
            if self.peri.reator.ativo() then
                self.peri.reator.setAtivo(false)
                self.peri.reator.setBarras(100)
            end
            return
        end

        if self.estado == M.ESTADOS.CALIBRANDO then
            -- O controle e assumido temporariamente pela rotina de calibracao
            return
        end

        self:determinarModo()

        if self.modo == "ATIVO_TURBINA" and #self.peri.turbinas > 0 then
            self:processarAtivoComTurbinas()
        else
            self:processarPassivo()
        end

        self.stats.tempo_operacao = self.stats.tempo_operacao + self.cfg.ativo.sistema.intervalo_tick
    end

    -- Coleta um instantaneo de dados atualizados para relatorios e interface
    function c:coletarSnapshot()
        local r = self.peri.reator
        local dados = {
            tempo = os and (os.date and os.date("%Y-%m-%d %H:%M:%S") or os.time()) or "0",
            modo = self.modo,
            estado = self.estado,
            alerta = self.motivo_alerta,
            reator = nil,
            turbinas = {},
            eficiencia_rf_mb = math.floor(self.stats.eficiencia_media_rf_mb),
            barras_alvo = self.stats.barras_alvo,
        }

        if r then
            dados.reator = {
                nome = r.nome,
                ativo = r.ativo(),
                temp_combustivel = r.tempCombustivel(),
                temp_carcaca = r.tempCarcaca(),
                energia_armazenada = r.energiaArmazenada(),
                energia_capacidade = r.energiaCapacidade(),
                energia_pct = r.energiaPorcentagem(),
                energia_tick = r.energiaProduzidaTick(),
                vapor_tick = r.vaporProduzidoTick(),
                combustivel_armazenado = r.combustivelArmazenado(),
                combustivel_max = r.combustivelMax(),
                combustivel_pct = r.combustivelPorcentagem(),
                lixo_armazenado = r.lixoArmazenado(),
                consumo_tick = r.consumoCombustivelTick(),
                reatividade = r.reatividade(),
                ativo_refrigerado = r.isAtivoRefrigerado(),
                agua = r.liquidoRefrigerante(),
                agua_max = r.liquidoRefrigeranteMax(),
                vapor = r.vaporArmazenado(),
                vapor_max = r.vaporMax(),
                barras_nivel = r.getNivelBarras(),
            }
        end

        for _, t in ipairs(self.peri.turbinas) do
            table.insert(dados.turbinas, {
                nome = t.nome,
                ativo = t.ativo(),
                rpm = t.rpm(),
                indutor = t.indutorAtivo(),
                vazao_atual = t.vazaoAtual(),
                vazao_max = t.vazaoMax(),
                energia_tick = t.energiaProduzidaTick(),
                energia_armazenada = t.energiaArmazenada(),
                energia_capacidade = t.energiaCapacidade(),
                eficiencia_pas = t.eficienciaPas(),
            })
        end

        return dados
    end

    return c
end

return M
