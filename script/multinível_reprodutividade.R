# =========================================================

# TÍTULO: Simulação de Modelos Multinível em Ciência Política
# OBJETIVO: Demonstrar, de forma didática, as diferenças entre:

# (1) MQO convencional (complete pooling)
# (2) Modelos com efeitos fixos (no pooling)
# (3) Modelos multinível (partial pooling / shrinkage)

# O script acompanha a nota técnica sobre modelagem
# multinível aplicada à Ciência Política.

# REPRODUTIBILIDADE: Todas as análises são simuladas com semente fixa.

# =========================================================
# 1. PACOTES ----------------------------------------------
# =========================================================

library(tidyverse)
library(lme4)
library(performance)
library(knitr)
library(kableExtra)

# =========================================================
# 2. REPRODUTIBILIDADE ------------------------------------
# =========================================================

set.seed(123)

# =========================================================
# 3. PARÂMETROS DA SIMULAÇÃO ------------------------------
# =========================================================

n_paises <- 50
n_individuos_por_pais <- 1000
total_individuos <- n_paises * n_individuos_por_pais

# =========================================================
# 4. SIMULAÇÃO DO NÍVEL 2 (PAÍSES) ------------------------
# =========================================================

# Variáveis contextuais: PIB, desemprego, inflação
# Essas variáveis produzirão heterogeneidade entre os países.

# =========================================================

paises <- tibble(
  pais_id = 1:n_paises,
  pib = rnorm(n_paises, mean = 10, sd = 3),
  desemprego = rnorm(n_paises, mean = 8, sd = 3),
  inflacao = rnorm(n_paises, mean = 5, sd = 2)
)

# =========================================================
# 5. EXPANSÃO PARA O NÍVEL INDIVIDUAL ---------------------
# =========================================================

# Variáveis individuais: renda, situação de trabalho, sexo

# =========================================================

dados <- paises %>%
  slice(rep(1:n(), each = n_individuos_por_pais)) %>%
  mutate(
    id_indiv = 1:total_individuos,
    renda = runif(total_individuos, 1, 10),
    trabalha = rbinom(total_individuos, 1, 0.6),
    sexo = rbinom(total_individuos, 1, 0.5)
  ) %>%
  mutate(
    renda_z = scale(renda)[, 1]
  )

# =========================================================
# 6. GERAÇÃO DA VARIÁVEL DEPENDENTE -----------------------
# =========================================================

# A avaliação da democracia é influenciada por:
# (a) efeitos contextuais (nível 2)
# (b) efeitos individuais (nível 1)

# Isso cria dependência intragrupo e justifica o uso da modelagem multinível.

# =========================================================

dados <- dados %>%
  mutate(
    
    # Efeito contextual
    efeito_pais =
      0.7 * pib -
      0.5 * desemprego -
      0.6 * inflacao,
    
    # Efeito individual
    efeito_ind =
      0.8 * renda_z +
      0.7 * trabalha +
      0.5 * sexo,
    
    # Variável dependente
    avaliacao_democracia =
      5 +
      efeito_pais +
      efeito_ind +
      rnorm(n(), 0, 1)

  ) %>%
  mutate(
    avaliacao_democracia =
      pmin(pmax(avaliacao_democracia, 0), 10)
  )

# =========================================================
# 7. INSPEÇÃO DOS DADOS -----------------------------------
# =========================================================

summary(dados)

# =========================================================
# 8. MODELOS MULTINÍVEL -----------------------------------
# =========================================================

# 8.1 Modelo nulo -----------------------------------------
# Apenas intercepto aleatório

modelo_nulo <- lmer(
  avaliacao_democracia ~ 1 + (1 | pais_id),
  data = dados
)

# 8.2 Modelo com variáveis individuais --------------------

modelo_nivel1 <- lmer(
  avaliacao_democracia ~
    renda_z +
    trabalha +
    sexo +
    (1 | pais_id),
  data = dados
)

# 8.3 Modelo completo -------------------------------------
# Variáveis de nível 1 + nível 2

modelo_completo <- lmer(
  avaliacao_democracia ~
    renda_z +
    trabalha +
    sexo +
    pib +
    desemprego +
    inflacao +
    (1 | pais_id),
  data = dados
)

# =========================================================
# 9. QUALIDADE DOS AJUSTES --------------------------------
# =========================================================

modelos_ml <- list(
  Nulo = modelo_nulo,
  Nivel1 = modelo_nivel1,
  Completo = modelo_completo
)

ajustes_ml <- map_dfr(
  modelos_ml,
  ~ tibble(
    logLik = round(as.numeric(logLik(.)), 2),
    AIC = round(AIC(.), 2),
    BIC = round(BIC(.), 2),
    R2 = round(r2(.)$R2_marginal, 3),
    ICC = round(icc(.)$ICC_adjusted, 3)
  ),
  .id = "Modelo"
)

print(ajustes_ml)

# =========================================================
# 10. VISUALIZAÇÃO: R² E ICC ------------------------------
# =========================================================

ajustes_long <- ajustes_ml %>%
  select(Modelo, R2, ICC) %>%
  pivot_longer(
    cols = c(R2, ICC),
    names_to = "Metrica",
    values_to = "Valor"
  )

ajustes_long <- ajustes_long %>%
  mutate(
    Modelo = factor(
      Modelo,
      levels = c("Nulo", "Nivel1", "Completo")
    )
  )

ggplot(
  ajustes_long,
  aes(x = Modelo, y = Valor, fill = Metrica)
) +
  geom_col(
    position = "dodge",
    width = 0.6
  ) +
  geom_text(
    aes(label = round(Valor, 2)),
    position = position_dodge(width = 0.6),
    vjust = -0.5,
    size = 4.5
  ) +
  scale_fill_manual(
    values = c(
      "R2" = "#1b9e77",
      "ICC" = "#d95f02"
    )
  ) +
  labs(
    x = NULL,
    y = NULL,
    fill = "Métrica"
  ) +
  ylim(0, 1) +
  theme_minimal(base_size = 14)

# =========================================================
# 11. TESTES DE RAZÃO DE VEROSSIMILHANÇA (LRT) ------------
# =========================================================

teste_n1_vs_nulo <- anova(
  modelo_nulo,
  modelo_nivel1
)

teste_completo_vs_n1 <- anova(
  modelo_nivel1,
  modelo_completo
)

print(teste_n1_vs_nulo)
print(teste_completo_vs_n1)

# =========================================================
# 12. TABELA DOS TESTES LRT -------------------------------
# =========================================================

tabela_lrt <- tibble(
  Comparacao = c(
    "Nível 1 vs Nulo",
    "Completo vs Nível 1"
  ),
  Chisq = c(28113, 189.5),
  Df = c(3, 3),
  p_valor = c("< 2.2e-16", "< 2.2e-16")
)

kable(
  tabela_lrt,
  format = "html"
) %>%
  kable_styling(
    full_width = FALSE,
    bootstrap_options = c(
      "striped",
      "hover",
      "condensed"
    )
  )

# =========================================================
# 13. RESUMO DO MODELO COMPLETO ---------------------------
# =========================================================

summary(modelo_completo)

# =========================================================
# 14. EFEITOS ALEATÓRIOS DOS PAÍSES -----------------------
# =========================================================

efeitos_pais <- ranef(modelo_completo)$pais_id %>%
  as_tibble(rownames = "pais_id") %>%
  rename(intercepto = `(Intercept)`)

efeitos_pais <- efeitos_pais %>%
  mutate(
    pais_id = factor(
      pais_id,
      levels = pais_id[order(intercepto)]
    )
  )

ggplot(
  efeitos_pais,
  aes(x = pais_id, y = intercepto)
) +
  geom_col(fill = "#1f77b4") +
  coord_flip() +
  labs(
    x = "País (ID)",
    y = "Efeito aleatório"
  ) +
  theme_minimal(base_size = 8)

# =========================================================
# 15. MODELO COM INTERAÇÃO ENTRE NÍVEIS -------------------
# =========================================================

# Interação:
# renda individual × PIB do país

# =========================================================

modelo_interacao <- lmer(
  avaliacao_democracia ~
    renda_z * pib +
    trabalha +
    sexo +
    desemprego +
    inflacao +
    (1 | pais_id),
  data = dados
)

summary(modelo_interacao)

# =========================================================
# 16. EFEITO MARGINAL DA RENDA AO LONGO DO PIB ------------
# =========================================================

pib_seq <- seq(5, 55, by = 0.5)

efeito_renda <- 0.927256 + (-0.018980) * pib_seq

df_efeito <- data.frame(
  pib = pib_seq,
  efeito_renda = efeito_renda
)

ponto_zero <- 0.927256 / 0.018980

ggplot(
  df_efeito,
  aes(x = pib, y = efeito_renda)
) +
  geom_smooth(
    color = "#1b9e77",
    size = 1.2
  ) +
  geom_hline(
    yintercept = 0,
    linetype = "dashed",
    color = "gray40"
  ) +
  geom_vline(
    xintercept = ponto_zero,
    linetype = "dotted",
    color = "red"
  ) +
  annotate(
    "text",
    x = ponto_zero + 1,
    y = 0.2,
    label = paste0(
      "PIB ≈ ",
      round(ponto_zero, 1)
    ),
    color = "red",
    size = 5
  ) +
  labs(
    title = "Efeito marginal da renda",
    subtitle = "Interação entre renda e PIB",
    x = "PIB do país",
    y = "Efeito marginal da renda"
  ) +
  theme_minimal(base_size = 14)

# =========================================================
# 17. VISUALIZAÇÃO DA INTERAÇÃO ---------------------------
# =========================================================

pib_vals <- c(6, 10, 14)

renda_seq <- seq(
  -3,
  3,
  length.out = 100
)

efeito_renda_inter <- lapply(
  pib_vals,
  function(pib) {
    0.927256 + (-0.018980) * pib
  }
) %>%
  unlist()

df_interacao <- expand.grid(
  renda_z = renda_seq,
  tipo = c(
    "Renda isolada",
    paste0(
      "Renda × PIB = ",
      pib_vals
    )
  )
) %>%
  mutate(
    efeito = case_when(
      
      tipo == "Renda isolada" ~
        0.927256 * renda_z,
      
      tipo == paste0("Renda × PIB = ", pib_vals[1]) ~
        efeito_renda_inter[1] * renda_z,
      
      tipo == paste0("Renda × PIB = ", pib_vals[2]) ~
        efeito_renda_inter[2] * renda_z,
      
      tipo == paste0("Renda × PIB = ", pib_vals[3]) ~
        efeito_renda_inter[3] * renda_z,
      
      TRUE ~ NA_real_
    )
    
  )

ggplot(
  df_interacao,
  aes(
    x = renda_z,
    y = efeito,
    color = tipo
  )
) +
  geom_line(size = 1.2) +
  labs(
    x = "Renda padronizada",
    y = "Efeito marginal",
    color = "Modelo"
  ) +
  theme_minimal(base_size = 14)

# =========================================================
# 18. COMPARAÇÃO ENTRE MQO, FE E MLH ----------------------
# =========================================================

# 18.1 MQO convencional -----------------------------------
# Complete pooling

modelo_mqo <- lm(
  avaliacao_democracia ~
    renda_z +
    trabalha +
    sexo +
    pib +
    desemprego +
    inflacao,
  data = dados
)

# 18.2 Efeitos fixos --------------------------------------
# No pooling

modelo_fe <- lm(
  avaliacao_democracia ~
    renda_z +
    trabalha +
    sexo +
    factor(pais_id),
  data = dados
)

# =========================================================
# 19. COMPARAÇÃO DOS MODELOS ------------------------------
# =========================================================

AIC(
  modelo_mqo,
  modelo_fe,
  modelo_completo
)

BIC(
  modelo_mqo,
  modelo_fe,
  modelo_completo
)

# =========================================================
# 20. RESUMOS FINAIS --------------------------------------
# =========================================================

summary(modelo_mqo)
summary(modelo_fe)
summary(modelo_completo)
summary(modelo_interacao)

# =========================================================
# FIM DO SCRIPT -------------------------------------------
# =========================================================
