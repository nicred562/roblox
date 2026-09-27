# Supermercado Together (Roblox)

Simulador de supermercado **cooperativo en primera persona**, inspirado en las mecánicas de *Supermarket Together*.
Todo está hecho por código (el mundo, los muebles, los productos y la interfaz): no hace falta modelar nada en Studio.

> Los gráficos y modelos del juego original pertenecen a sus desarrolladores y no se copian: este proyecto recrea
> **sus mecánicas** con piezas propias de Roblox, en un estilo parecido (colorido, low-poly, primera persona).

## Qué tiene

| Sistema | Cómo funciona |
|---|---|
| 🏠 Menú principal | Lista de salas abiertas, **crear sala con nombre y contraseña**, unirse con contraseña, "Mis supermercados" |
| 🔐 Salas privadas | Cada sala es un servidor reservado con su propio guardado; el dueño pasa la contraseña por otros medios |
| 🏘️ Barrio | Calles, veredas, cruce peatonal, faroles que se prenden de noche, árboles y ~30 casas; los clientes salen de las casas |
| 🏪 Edificio | Vidrieras, puertas automáticas, tienda con baldosas, depósito con portón, oficina del gerente, estacionamiento con autos |
| 🔨 Construcción (TAB) | Arrancás con **$5,000 y el local vacío**: estanterías, heladeras, freezers, cajas, autocajas, estantes de depósito y decoración. Mover (Q), rotar (R), vender (X) |
| 📦 Pedidos | Pizarra del gerente con carrito; las cajas llegan a la **zona de descarga** afuera del portón |
| 🧺 Reposición | Primera persona: levantás la caja y **ponés los productos de a uno con click** (mantener = rápido). Click derecho saca. Cada nivel tiene su etiqueta de precio |
| 🗄️ Depósito | Estantes con 10 lugares para cajas, con etiqueta automática |
| ♻️ Reciclaje | Cajas vacías al tacho azul: **+$1.50** cada una ($2.50 con la mejora) |
| 🏷️ Pistola de precios | Apuntás a un producto y cambiás el precio con la rueda del mouse. Hasta **2x el precio de mercado** compran; más, se quejan |
| 📈 Inflación | Los **jueves** suben los precios de mercado |
| 🧾 Caja registradora | Los clientes ponen los productos en la **cinta**; los escaneás con click. **Tarjeta**: tipeás el total. **Efectivo**: armás el vuelto (si das de más, lo perdés) |
| 🦹 Ladrones | Desde el día 7. Se marcan con un ícono y corren a la calle: **escobazo** = se caen y tiran lo robado. Si las cajas están llenas o tardás, también roban |
| 🧹 Limpieza | La basura baja la satisfacción: se barre con la escoba |
| 🕒 Día | **Botón verde** abre a las 08:00 · a las 22:30 no entran más clientes · **botón rojo** cierra |
| 📊 Fin del día | Reporte con ventas, **facturas** (alquiler, luz, sueldos), robos y préstamo |
| ⭐ Niveles y franquicia | La experiencia sale de cada producto vendido; cada nivel da 1 **punto de franquicia** para la pizarra (productos, empleados, marketing, wifi, aire acondicionado, reciclaje, logística, autocajas...) |
| 🏗️ Ampliaciones | Con dinero: ampliación del depósito, tienda trasera y ala derecha |
| 👷 Empleados | Cajero, Repositor, Depósito y Seguridad, con sueldo diario |
| 🏦 Préstamos | 3 tamaños con interés y cuotas diarias. **Si no pagás, vienen cobradores**: te persiguen, te pegan y se llevan la plata (+20%). Se los echa a escobazos, pero vuelven |
| 🎨 Personalizar | Colores de piso, paredes y cartel, nombre del súper (filtrado), contraseña de la sala |
| 📋 Tutorial | Panel de "Primeros pasos" que se va tildando solo |
| 💾 Guardado | Muebles, productos, cajas, empleados, precios, nivel, préstamo y personalización |

## Estructura

```
src/
  shared/                       -> ReplicatedStorage/Shared (Folder)
    Config.luau                    ModuleScript: productos, muebles, mejoras, préstamos, horarios...
    Remotes.luau                   ModuleScript
  server/                       -> ServerScriptService
    GameServer.server.luau         Script (punto de entrada)
    Modules/                       Folder con 17 ModuleScripts:
      State, StoreBuilder, Products, NPC, Fixtures, Boxes, Checkouts, Trash, Customers,
      Loans, Tools, Employees, Upgrades, Office, Rooms, Persistence, DayCycle
  client/                       -> StarterPlayer/StarterPlayerScripts
    LobbyClient.client.luau        LocalScript (menú principal)
    ClientMain.client.luau         LocalScript (interfaz del supermercado)
```

## Instalación

### Opción A: a mano en Roblox Studio

1. Lugar nuevo con la plantilla **Baseplate**.
2. **ReplicatedStorage** → Folder `Shared` → ModuleScripts `Config` y `Remotes`.
3. **ServerScriptService** → Script `GameServer` + Folder `Modules` con los 17 ModuleScripts (mismo nombre que el archivo, sin `.luau`).
4. **StarterPlayer → StarterPlayerScripts** → LocalScripts `LobbyClient` y `ClientMain`.
5. **Ojo con las mayúsculas** y con pegar el archivo completo (Ctrl+A en el archivo). Si algo está mal, la Salida lo avisa con `❌`.
6. Si venís de la versión anterior: **borrá** los módulos `Shelves`, `Registers` y `Computer`.

### Opción B: con Rojo

`rojo serve` en esta carpeta y conectá el plugin de Rojo en Studio.

## Probar

- **En Studio** (Probar / F5): aparece el menú. Al crear una sala, el supermercado se carga en el mismo servidor
  (los teleports a salas reales solo funcionan en el juego publicado).
- **Guardado en Studio**: Game Settings → Security → *Enable Studio Access to API Services*.
- **Con amigos**: publicá el juego (File → Publish to Roblox), activá API Services, y en *Game Settings → Places*
  poné el máximo de jugadores que quieras. Creá una sala y pasales el nombre y la contraseña.

## Controles

| Tecla | Acción |
|---|---|
| Click | Levantar caja · poner producto (mantener) · escanear · cobrar |
| Click derecho | Sacar producto del estante a la caja |
| F | Soltar caja |
| 1 / 2 | Escoba / Pistola de precios |
| Rueda o Z/X | Cambiar precio (Shift ±0.01, Ctrl ±1.00) |
| TAB | Modo construcción (R rotar, Q mover, X vender, click der. mantener = mirar) |
| H | Ayuda |
| E | Botones y pizarras (ProximityPrompts) |

## Personalizar el juego

Casi todo está en `Config.luau`: dinero inicial, duración del día, productos (con forma, tamaño, colores y precio),
muebles, mejoras de franquicia, ampliaciones, préstamos, sueldos, ladrones y cobradores.
