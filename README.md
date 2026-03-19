# dei_drift

Sistema de drift con puntuacion, combos y recompensa de dinero.

## Requisitos

- FiveM Server
- ESX o QBCore

## Instalacion

1. Descarga el recurso
2. Coloca la carpeta `dei_drift` en tu directorio `resources`
3. Agrega `ensure dei_drift` a tu `server.cfg`
4. Configura `config.lua` a tu gusto

## Configuracion

Edita `config.lua` para ajustar los multiplicadores de puntuacion, recompensas de dinero y parametros de combo.

## Ecosistema Dei

Este recurso forma parte del ecosistema Dei. Funciona de forma independiente, pero al usarlo junto a otros recursos Dei comparte:

- Sistema de temas (dark, midnight, neon, minimal)
- Modo claro/oscuro
- Preferencias sincronizadas via KVP

## Estructura

```
dei_drift/
├── client/
│   ├── framework.lua
│   └── main.lua
├── server/
│   ├── framework.lua
│   └── main.lua
├── shared/
│   └── utils.lua
├── html/
│   ├── index.html
│   └── assets/
│       ├── css/
│       │   ├── styles.css
│       │   └── themes.css
│       ├── js/
│       │   └── app.js
│       └── fonts/
│           ├── Gilroy-Light.otf
│           └── Gilroy-ExtraBold.otf
├── config.lua
└── fxmanifest.lua
```

## Licencia

MIT License - Dei
