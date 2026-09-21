# Email marketing: cómo dejarlo andando

El código ya está hecho y desplegado. La función `enviar-campana` está en
Supabase y, hasta que se configure, contesta un mensaje claro en la app
("El envío de mails todavía no está configurado…") en vez del error 404 que
aparecía antes. La campaña queda como borrador y se puede mandar después.

Lo que falta son **dos datos que solo puede cargar el dueño de la cuenta**:
la clave de Resend y el remitente. Son unos 20 minutos, más lo que tarde el
DNS en propagarse (entre minutos y unas horas).

> La clave **nunca** se pega en el chat, en el código ni en un mail. Va
> directo al panel de Supabase, que la guarda cifrada.

---

## 1. Crear la cuenta en Resend

1. Entrá a <https://resend.com> y creá la cuenta (podés entrar con Google o
   GitHub).
2. El plan gratis alcanza para arrancar: **3.000 mails por mes, hasta 100 por
   día**. Una campaña a más de 100 personas en un mismo día necesita el plan
   pago (o mandarla en tandas).

## 2. Verificar el dominio de la agencia

Sin dominio verificado, Resend solo deja mandar mails **a tu propia casilla**
(sirve para probar, ver el paso 5). Para mandarle a clientes hace falta
demostrar que el dominio es de la agencia.

1. En Resend: **Domains → Add Domain**. Escribí el dominio de la agencia
   (por ejemplo `automotoreseloeste.com.ar`). Región: la que venga por
   defecto.
2. Resend te muestra 3 o 4 registros DNS (un **MX** y un **TXT** para `send`,
   un **TXT** para `resend._domainkey`, y opcionalmente uno de DMARC).
3. Entrá a donde está administrado el dominio (NIC Argentina delega en el
   proveedor de hosting o en Cloudflare, según cómo lo hayan configurado) y
   cargá esos registros **tal cual**, copiando y pegando.
4. Volvé a Resend y tocá **Verify**. Si no pasa enseguida, esperá un rato: el
   DNS tarda.

> Si la agencia no tiene dominio propio (usa un Gmail), no se puede mandar
> marketing "a nombre de" ese Gmail desde ningún servicio serio. La opción es
> comprar un dominio `.com.ar` (en NIC Argentina es barato) y usarlo solo
> para esto.

## 3. Crear la API key

1. En Resend: **API Keys → Create API Key**.
2. Nombre: `mi-agencia`. Permiso: **Sending access**. Dominio: el que
   verificaste.
3. Copiá la clave (empieza con `re_`). Resend la muestra **una sola vez**.

## 4. Cargar los dos secretos en Supabase

1. Entrá al panel del proyecto:
   <https://supabase.com/dashboard/project/zthpwqcoirrpvslambhz/functions/secrets>
   (**Edge Functions → Secrets**).
2. Agregá:

   | Nombre | Valor |
   |---|---|
   | `RESEND_API_KEY` | la clave `re_...` del paso 3 |
   | `RESEND_FROM` | `Automotores El Oeste <novedades@automotoreseloeste.com.ar>` |

   La dirección de `RESEND_FROM` tiene que ser **del dominio verificado**. El
   nombre visible lo reemplaza el nombre de la agencia (o el de la campaña, si
   le pusieron uno).
3. Guardá. No hace falta volver a desplegar nada: la función lee los
   secretos en cada envío.

## 5. Probar

1. **En la app → Configuración**, completá el **email de contacto** de la
   agencia. Es a donde llegan las respuestas de los clientes (incluido el
   "BAJA" que ofrece el pie del mail). Sin eso, las respuestas se pierden.
2. Cargá un interesado con **tu propio email** y activá "Acepta recibir
   novedades por email".
3. Armá una campaña de prueba y mandala. Tendría que llegarte en segundos.
   Si no, revisá la carpeta de spam y **Emails** en el panel de Resend, que
   muestra cada envío y por qué falló.

> **Para probar antes de tener el dominio:** poné
> `RESEND_FROM` = `Prueba <onboarding@resend.dev>`. Solo llega a la casilla
> con la que creaste la cuenta de Resend, pero alcanza para ver que todo el
> circuito anda.

---

## Qué pasa si algo falla

| Lo que dice la app | Qué significa |
|---|---|
| "El envío de mails todavía no está configurado…" | Falta alguno de los dos secretos del paso 4. |
| "No salió ningún mail. Resend respondió: …" | Resend rechazó el envío. El motivo va en el mensaje; casi siempre es el dominio sin verificar o un `RESEND_FROM` de otro dominio. La campaña vuelve a borrador para reintentarla. |
| "No hay destinatarios que cumplan el filtro." | Ningún interesado con email aceptó recibir novedades. Se marca en la ficha de cada uno. |
| "Esa campaña ya se envió." | Protección contra el doble toque: una campaña enviada no se reenvía. Duplicala. |

## Por qué no se manda desde la app

La clave de Resend permite mandar mails a nombre del dominio de la agencia.
Una app instalada se puede desarmar y leer: si la clave viajara adentro,
cualquiera con el instalador podría usarla. Por eso vive en Supabase y la
usa solo la función del servidor.
