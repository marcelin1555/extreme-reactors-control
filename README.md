# Extreme Reactors Control v2.0 (CC: Tweaked)

Sistema autônomo e de alta eficiência para gerenciamento de Reatores Nucleares (**Extreme Reactors** / **Big Reactors**) utilizando computadores do **CC: Tweaked** (ComputerCraft).

---

## ⚡ Principais Funcionalidades

1. **Suporte Híbrido Automático (Passivo ou Ativo com Turbinas)**:
   - **Modo Passivo (Somente Reator)**:
     - Geração direta de RF/FE.
     - Modulação inteligente e dinâmica das barras de controle baseada no nível do buffer elétrico e na curva térmica do combustível.
     - Freio térmico para evitar superaquecimento (>850°C onde o consumo de urânio dispara sem ganho proporcional).
     - Histerese para desligamento/espera em buffer cheio (>88%), evitando desperdício de combustível.
   - **Modo Ativo (Reator Refrigerado + Turbina[s])**:
     - Suporte a 1 ou múltiplas turbinas simultâneas.
     - **Travamento em 1800 RPM**: Ponto clássico de 100% de rendimento aerodinâmico das pás da turbina.
     - **Controle Dinâmico de Indutor**: Indutor desengajado na partida para rápida aceleração sem carga magnética; engajamento automático ao atingir 1792-1800 RPM.
     - **Controle de Vazão de Vapor**: Modula `setFluidFlowRateMax` em tempo real para compensar variações de carga e manter a rotação estabilizada.
     - **Balanceamento do Reator**: As barras de controle do reator modulam para produzir exatamente a quantidade de vapor consumida pela soma das turbinas.

2. **Gerador de Relatórios e Telemetria para Desenvolvimento**:
   - **Relatório Analítico Completo (`.txt`)**: Pressione `[R]` no teclado a qualquer momento para gerar um snapshot detalhado com estatísticas de consumo, rendimento, temperaturas e dicas de engenharia em `relatorios/relatorio_<data>.txt`.
   - **Telemetria Contínua em CSV**: Registro automático em `relatorios/telemetria.csv` com colunas de RF/t, mB/t de combustível, Eficiência (RF/mB), Temperaturas, Buffer % e RPM para análise e gráficos.
   - **Auto-Calibração / Benchmark de Rendimento**: Pressione `[C]` para executar um teste padronizado (0%, 20%, 40%, 60%, 80% de barras) que estabiliza e aponta o ponto de máxima eficiência do seu projeto.

3. **Interface Visual Moderna**:
   - Dashboard gráfico para a tela do computador ou monitor externo (avançado ou comum).
   - Barras de progresso coloridas de Buffer, Temperatura, Combustível e RPM.
   - Indicador de eficiência em destaque: `RF / mB`.
   - Alertas térmicos e travas de segurança (**SCRAM** automático e manual).

---

## 🔌 Conexão dos Componentes no Minecraft

### 1. Reator
- Adicione um bloco **Reactor Computer Port** na estrutura do reator.
- Coloque o computador do CC: Tweaked diretamente encostado no bloco OU conecte um **Wired Modem** no Computer Port e no Computador, clicando com o botão direito para ativar os modems (linha vermelha).

### 2. Turbinas (se houver)
- Adicione um **Turbine Computer Port** na estrutura da(s) turbina(s).
- Conecte via **Wired Modem** à mesma rede de cabos do computador.
- Certifique-se de que a água e o vapor estejam conectados em ciclo fechado entre o reator e as turbinas (com canos de fluido ou portas de acesso direto).

### 3. Monitor Externo (Opcional)
- Monte um monitor (ex: 2x2, 3x2 ou 4x3) encostado no computador ou conectado via rede cabeada. O sistema detectará e renderizará a telemetria automaticamente nele!

---

## 🚀 Como Instalar e Rodar

### Opção A: Instalação Direta via wget no Minecraft (Recomendado)
No terminal do computador CC: Tweaked (com modem de internet ou HTTP habilitado), execute:
```bash
wget run https://raw.githubusercontent.com/marcelin1555/extreme-reactors-control/main/instalar.lua
```
Ou se preferir baixar antes de rodar:
```bash
wget https://raw.githubusercontent.com/marcelin1555/extreme-reactors-control/main/instalar.lua instalar.lua
instalar
```
Ele extrairá todos os arquivos necessários e criará a pasta de relatórios automaticamente.

### Opção B: Arquivos Individuais
Coloque os seguintes arquivos no diretório raiz do computador CC:
- `startup.lua`
- `config.lua`
- `perifericos.lua`
- `controlador.lua`
- `relatorios.lua`
- `interface.lua`

Para iniciar:
```bash
startup              # Inicia no perfil salvo
startup --potencia   # Inicia forçando perfil de MÁXIMA POTÊNCIA
startup --eficiencia # Inicia forçando perfil de ECO EFICIÊNCIA
```

---

## ⌨️ Teclas de Atalho do Painel

| Tecla | Ação | Descrição |
|---|---|---|
| `[P]` | **Alternar Perfil** | Alterna entre **MÁXIMA POTÊNCIA** (barras a 0%, geração máxima) e **ECO EFICIÊNCIA** (economia de urânio) |
| `[R]` | **Gerar Relatório** | Salva um relatório analítico instantâneo em `relatorios/relatorio_*.txt` |
| `[C]` | **Benchmark** | Executa a varredura e aponta a melhor potência bruta e melhor eficiência |
| `[E]` | **SCRAM** | Alterna o desligamento de emergência manual (trava reator e turbinas) |
| `[Q]` | **Sair** | Encerra o sistema com segurança e retorna ao prompt do shell |

---

## ⚙️ Perfis de Operação

- **⚡ MÁXIMA POTÊNCIA (`POTENCIA`)**:
  - As barras de controle são mantidas em **0%** para entregar a máxima taxa de reação e a maior geração de RF/t e Vapor/t possíveis.
  - Acelera a queima sem limitar o reator a temperaturas baixas, operando até **1350°C** com freio térmico automático preventivo para nunca atingir o SCRAM de 1500°C.
  - Nas turbinas, libera a vazão total de vapor suportada pelo hardware para o pico elétrico.
- **🌱 ECO EFICIÊNCIA (`EFICIENCIA`)**:
  - Modula suavemente as barras para manter a temperatura em torno de **650°C**, faixa onde a queima de urânio é mínima por cada RF produzido.
  - Histerese de buffer (desliga quando a rede estiver cheia).

---

## ⚙️ Configurações Customizáveis (`config.lua`)

Você pode editar `config.lua` ou alterar os valores no arquivo:
- `perfil_operacao`: `"potencia"` ou `"eficiencia"`.
- `reator.temp_max_potencia`: Temperatura teto de trabalho em potência máxima (padrão: `1350°C`).
- `reator.buffer_energia_min`: Porcentagem mínima de energia antes de ligar o reator (padrão: `25%`).
- `reator.buffer_energia_max`: Porcentagem máxima de energia antes de reduzir/desligar (padrão: `88%`).
- `reator.temp_alvo_combustivel`: Temperatura ideal para consumo eficiente (padrão: `650°C`).
- `turbina.rpm_alvo`: Rotação de máxima eficiência aerodinâmica (padrão: `1800 RPM`).
- `turbina.rpm_engajar_indutor`: Rotação para engajar a bobina (padrão: `1792 RPM`).
- `sistema.intervalo_telemetria_csv`: Intervalo em segundos para registrar no CSV (padrão: `5s`).
