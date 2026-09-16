-- interface.lua
-- Interface Visual Rica para Terminal do Computador e Monitores do CC: Tweaked

local M = {}

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

function M.novo(dispositivoSaida)
    local ui = {
        term = dispositivoSaida or term,
        notificacao = nil,
        tempoNotificacao = 0,
    }

    function ui:definirDispositivo(d)
        self.term = d or term
    end

    function ui:notificar(msg)
        self.notificacao = msg
        self.tempoNotificacao = os.clock and os.clock() or 0
    end

    -- Desenha barra de progresso horizontal
    function ui:barraProgresso(x, y, largura, porcentagem, corCheio, corVazio)
        porcentagem = math.max(0, math.min(100, porcentagem or 0))
        local preenchido = math.floor((porcentagem / 100) * largura)
        local vazio = largura - preenchido

        self.term.setCursorPos(x, y)
        if self.term.isColor and self.term.isColor() then
            self.term.setTextColor(corCheio or colors.green)
            self.term.write(string.rep("=", preenchido))
            self.term.setTextColor(corVazio or colors.gray)
            self.term.write(string.rep("-", vazio))
            self.term.setTextColor(colors.white)
        else
            self.term.write(string.rep("#", preenchido) .. string.rep("-", vazio))
        end
    end

    function ui:escrever(x, y, texto, corTexto, corFundo)
        local w, h = self.term.getSize()
        if y > h or y < 1 then return end
        self.term.setCursorPos(x, y)
        if self.term.isColor and self.term.isColor() then
            if corFundo then self.term.setBackgroundColor(corFundo) end
            if corTexto then self.term.setTextColor(corTexto) end
        end
        self.term.write(texto)
        if self.term.isColor and self.term.isColor() then
            self.term.setBackgroundColor(colors.black)
            self.term.setTextColor(colors.white)
        end
    end

    function ui:renderizar(dados)
        local t = self.term
        local w, h = t.getSize()
        local isColor = t.isColor and t.isColor()

        t.setBackgroundColor(colors.black)
        t.clear()

        -- 1. Cabecalho Superior
        t.setCursorPos(1, 1)
        t.setBackgroundColor(colors.gray)
        t.clearLine()
        
        if isColor then t.setTextColor(colors.yellow) end
        t.write(" EXTREME REACTORS ")
        if isColor then t.setTextColor(colors.white) end
        t.write("| Modo: " .. (dados.modo == "ATIVO_TURBINA" and "REATOR+TURBINA" or "REATOR PASSIVO"))

        local statusTxt = " [" .. tostring(dados.estado) .. "] "
        t.setCursorPos(math.max(1, w - #statusTxt + 1), 1)
        if isColor then
            if string.find(dados.estado, "SCRAM") then
                t.setTextColor(colors.red)
            elseif dados.estado == "OPERANDO" then
                t.setTextColor(colors.lime)
            else
                t.setTextColor(colors.orange)
            end
        end
        t.write(statusTxt)
        t.setBackgroundColor(colors.black)
        t.setTextColor(colors.white)

        -- 2. Secao Reator
        local r = dados.reator
        if not r then
            self:escrever(2, 3, "ERRO: Nenhum reator conectado!", colors.red)
            return
        end

        local lin = 3
        -- Barra de Buffer de Energia
        local pctEnergia = r.energia_pct or 0
        local txtEnergia = string.format("Buffer Energia: %5.1f%% (%s / %s RF)",
            pctEnergia, formatarNumero(r.energia_armazenada), formatarNumero(r.energia_capacidade))
        self:escrever(2, lin, txtEnergia, colors.cyan)
        lin = lin + 1
        self:barraProgresso(2, lin, math.min(30, w - 4), pctEnergia, colors.lightBlue, colors.gray)
        self:escrever(34, lin, string.format("+%s RF/t", formatarNumero(r.energia_tick)), colors.yellow)
        lin = lin + 2

        -- Temperatura do Combustivel e Carcaca
        local tempComb = r.temp_combustivel or 0
        local corTemp = colors.green
        if tempComb > 950 then
            corTemp = colors.red
        elseif tempComb > 750 then
            corTemp = colors.orange
        end

        local txtTemp = string.format("Temp Combustivel: %.1f C | Carcaca: %.1f C", tempComb, r.temp_carcaca or 0)
        self:escrever(2, lin, txtTemp, corTemp)
        lin = lin + 1
        local pctTemp = math.min(100, (tempComb / 1500) * 100)
        self:barraProgresso(2, lin, math.min(30, w - 4), pctTemp, corTemp, colors.gray)
        self:escrever(34, lin, string.format("Barras: %d%%", r.barras_nivel or 0), colors.white)
        lin = lin + 2

        -- Combustivel & Eficiencia
        local txtComb = string.format("Combustivel: %.1f%% (%s mB) | Queima: %.4f mB/t",
            r.combustivel_pct or 0, formatarNumero(r.combustivel_armazenado), r.consumo_tick or 0)
        self:escrever(2, lin, txtComb, colors.yellow)
        lin = lin + 1

        -- Indicador de Eficiencia em Destaque
        local txtEff = string.format("EFICIENCIA: %s RF / mB  (Alvo Barras: %d%%)",
            formatarNumero(dados.eficiencia_rf_mb or 0), dados.barras_alvo or 0)
        self:escrever(2, lin, txtEff, colors.lime)
        lin = lin + 2

        -- 3. Secao de Turbinas (se houver)
        local turbinas = dados.turbinas or {}
        if #turbinas > 0 and lin < (h - 3) then
            self:escrever(2, lin, string.format("--- TURBINAS (%d Conectadas) ---", #turbinas), colors.purple)
            lin = lin + 1
            for i, t in ipairs(turbinas) do
                if lin >= (h - 2) then break end
                local deltaRPM = math.abs((t.rpm or 0) - 1800)
                local corRpm = (deltaRPM <= 15) and colors.lime or (deltaRPM <= 50 and colors.yellow or colors.orange)
                local indutorTxt = t.indutor and "[INDUTOR: LIGADO]" or "[INDUTOR: DESLIGADO]"

                local linhaTurb = string.format("T#%d: %6.1f RPM %s | %s RF/t | %d mB/t",
                    i, t.rpm or 0, indutorTxt, formatarNumero(t.energia_tick), t.vazao_max or 0)
                self:escrever(2, lin, linhaTurb, corRpm)
                lin = lin + 1
            end
        elseif r.ativo_refrigerado and lin < (h - 3) then
            -- Reator refrigerado sem turbina direta
            local txtRefrig = string.format("Refrigerante: %s mB | Vapor: %s mB (+%s mB/t)",
                formatarNumero(r.agua), formatarNumero(r.vapor), formatarNumero(r.vapor_tick))
            self:escrever(2, lin, txtRefrig, colors.cyan)
            lin = lin + 1
        end

        -- 4. Notificacao / Alerta Flutuante
        if self.notificacao then
            local decorrido = (os.clock and os.clock() or 0) - self.tempoNotificacao
            if decorrido < 6 then
                self:escrever(2, h - 2, ">> " .. self.notificacao, colors.yellow)
            else
                self.notificacao = nil
            end
        elseif dados.alerta then
            local corAlerta = string.find(dados.alerta, "SCRAM") and colors.red or colors.lightGray
            self:escrever(2, h - 2, dados.alerta, corAlerta)
        end

        -- 5. Rodape de Teclas de Atalho
        t.setCursorPos(1, h)
        t.setBackgroundColor(colors.gray)
        t.clearLine()
        if isColor then t.setTextColor(colors.white) end
        t.write(" [R] Relatorio  [C] Benchmark  [E] SCRAM  [Q] Sair")
        t.setBackgroundColor(colors.black)
    end

    return ui
end

return M
