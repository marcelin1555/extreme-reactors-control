-- config.lua
-- Configuracoes do Sistema de Gerenciamento de Extreme Reactors
-- Todas as variaveis possuem valores padrao otimizados para maxima eficiencia

local M = {}

-- Configuracoes Padrao
M.padrao = {
    -- Modo de operacao: "auto" (detecta passivo ou ativo+turbina), "passivo", "ativo"
    modo_operacao = "auto",

    -- Perfil de Operação: "eficiencia" (menor queima de combustível) ou "potencia" (máxima geração de RF/t e vapor)
    perfil_operacao = "eficiencia",

    -- Parametros do Reator
    reator = {
        -- Limiares do Buffer de Energia (% de 0 a 100)
        buffer_energia_min = 25,   -- Se cair abaixo, aumenta producao
        buffer_energia_max = 88,   -- Se passar disso, reduz/desliga para evitar perda
        buffer_energia_alvo = 60,  -- Ponto de equilibrio da modulacao suave

        -- Parametros Termicos (°C)
        temp_alvo_combustivel = 650,  -- Temperatura ideal para consumo eficiente (Perfil Eficiência)
        temp_max_segura = 950,        -- Acima disso o consumo cresce desproporcionalmente
        temp_max_potencia = 1350,     -- Limite termico em modo Potencia (trabalha quente com seguranca)
        temp_scram = 1500,            -- Desligamento de emergencia forcado

        -- Barras de Controle (%)
        min_nivel_barras = 0,    -- 0% = barras recolhidas (potencia maxima)
        max_nivel_barras = 100,  -- 100% = barras totalmente inseridas (parada)
        passo_ajuste = 2,        -- Sensibilidade do ajuste por ciclo

        -- Manutencao
        auto_ejetar_lixo = true, -- Ejetar cianita/residuos automaticamente
    },

    -- Parametros das Turbinas
    turbina = {
        -- Rotação Alvo (1800 RPM é o ponto ideal clássico de aerodinâmica)
        rpm_alvo = 1800,
        rpm_tolerancia = 12,          -- Faixa estavel (1788 a 1812 RPM)
        rpm_engajar_indutor = 1792,   -- Engaja bobina quando atingir esse valor
        rpm_desengajar_indutor = 1680, -- Desengaja se cair abaixo para retomar giro rápido
        
        -- Controle de Fluxo de Vapor
        vazao_max_limite = 2000,      -- Limite padrao de mB/t de vapor
        passo_vazao = 25,             -- Ajuste fino de mB/t por tick de controle
        modo_respiro = "overflow",    -- "none", "overflow", "all"
    },

    -- Parametros do Sistema e Relatórios
    sistema = {
        intervalo_tick = 0.5,            -- Frequencia do loop de controle em segundos
        intervalo_telemetria_csv = 5,    -- Salva linha em CSV a cada X segundos (0 para desligar)
        arquivo_telemetria = "relatorios/telemetria.csv",
        pasta_relatorios = "relatorios/",
        manter_historico_pontos = 60,    -- Pontos guardados em memoria para calculo de medias
    }
}

-- Tabela ativa de configuracao
M.ativo = {}

-- Copia recursiva de tabelas
local function clonar(origem)
    local copia = {}
    for k, v in pairs(origem) do
        if type(v) == "table" then
            copia[k] = clonar(v)
        else
            copia[k] = v
        end
    end
    return copia
end

-- Mescla configuracoes parciais sobre a base
local function mesclar(base, nova)
    for k, v in pairs(nova) do
        if type(v) == "table" and type(base[k]) == "table" then
            mesclar(base[k], v)
        else
            base[k] = v
        end
    end
end

-- Inicializa com os valores padrao
M.ativo = clonar(M.padrao)

-- Caminho do arquivo no disco
local ARQUIVO_CFG = "config_reator.txt"

function M.salvar(caminho)
    caminho = caminho or ARQUIVO_CFG
    local arq = fs and fs.open(caminho, "w")
    if arq then
        arq.write(textutils.serialize(M.ativo))
        arq.close()
        return true
    end
    return false
end

function M.carregar(caminho)
    caminho = caminho or ARQUIVO_CFG
    if fs and fs.exists(caminho) then
        local arq = fs.open(caminho, "r")
        if arq then
            local conteudo = arq.readAll()
            arq.close()
            local dados = textutils.unserialize(conteudo)
            if type(dados) == "table" then
                mesclar(M.ativo, dados)
                return true
            end
        end
    end
    return false
end

return M
