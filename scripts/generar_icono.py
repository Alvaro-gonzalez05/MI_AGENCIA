# =====================================================================
#  Mi Agencia - el icono de la app
#
#      python scripts/generar_icono.py
#
#  Escribe los dos PNG maestros en app/assets/icono/. De ahi salen todos
#  los tamanos (Android y Windows) con:
#
#      dart run flutter_launcher_icons
#
#  Esta como script y no como PNG suelto a proposito: el icono se va a
#  querer retocar (otro amarillo, otra proporcion), y regenerarlo tiene que
#  ser cambiar un numero y correr esto, no abrir un editor y exportar
#  catorce archivos a mano.
#
#  El dibujo: la "M" de Mi Agencia en la tipografia de la app (IBM Plex
#  Sans Bold) y, abajo a la derecha, el punto del semaforo, que es la
#  funcion que define al producto.
#
#  Se probo primero con tres barras que suben, y se descarto por dos
#  razones: quedaba desbalanceada (el punto arriba de la barra derecha deja
#  hueca la esquina de enfrente) y se parecia demasiado al icono de Google
#  Analytics, que es exactamente lo que no queres en el telefono de un
#  cliente. La letra con la tipografia propia no se parece a nada mas y se
#  lee igual de bien a 32 px.
# =====================================================================

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Los mismos colores del tema (app/lib/core/tema/colores.dart).
NEGRO = (19, 19, 21, 255)        # Paleta.oscura.negro
NEGRO_ABAJO = (10, 10, 11, 255)  # Paleta.oscura.fondo
AMARILLO = (255, 200, 61, 255)   # Paleta.oscura.acento

LADO = 1024
RAIZ = Path(__file__).resolve().parent.parent
SALIDA = RAIZ / "app" / "assets" / "icono"
FUENTE = RAIZ / "app" / "assets" / "fuentes" / "IBMPlexSans-Bold.ttf"


def fondo(lado: int) -> Image.Image:
    """Negro con una caida de luz de arriba a abajo.

    Plano se ve muerto al lado de los iconos de cualquier telefono; el
    degradado es apenas perceptible pero le da volumen.
    """
    img = Image.new("RGBA", (lado, lado), NEGRO)
    dibujo = ImageDraw.Draw(img)
    for y in range(lado):
        t = y / (lado - 1)
        color = tuple(
            round(a + (b - a) * t)
            for a, b in zip(NEGRO, NEGRO_ABAJO)
        )
        dibujo.line([(0, y), (lado, y)], fill=color)
    return img


def marca(lado: int, alto_relativo: float) -> Image.Image:
    """La letra y el punto, sobre fondo transparente.

    `alto_relativo` es cuanto del lado ocupa el dibujo. Cambia entre el icono
    normal y el de Android: en Android el sistema recorta los bordes con la
    forma que tenga el launcher (circulo, gota, cuadrado redondeado), asi que
    ahi la marca tiene que entrar mas chica para que no le corte la cabeza.
    """
    img = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    dibujo = ImageDraw.Draw(img)

    alto = lado * alto_relativo
    fuente = ImageFont.truetype(str(FUENTE), size=round(alto * 1.34))

    # Se mide la tinta de verdad (anchor "ls", el trazo sin el interlineado de
    # la fuente) y se centra ESO. Centrar por la caja de la fuente deja la
    # letra corrida hacia arriba, porque esa caja incluye el espacio que la
    # tipografia reserva para acentos y colas que la "M" no usa.
    izq, arriba, der, abajo = dibujo.textbbox((0, 0), "M", font=fuente, anchor="ls")
    ancho_letra = der - izq
    alto_letra = abajo - arriba

    radio_punto = alto * 0.115
    aire = radio_punto * 0.95

    # El punto se cuelga del hombro derecho de la letra, asi que el conjunto
    # es mas ancho que la letra sola y hay que centrar el conjunto.
    ancho_total = ancho_letra + aire + radio_punto * 2
    x = (lado - ancho_total) / 2 - izq
    y = (lado + alto_letra) / 2 - abajo

    dibujo.text((x, y), "M", font=fuente, fill=AMARILLO, anchor="ls")

    cx = x + izq + ancho_letra + aire + radio_punto
    cy = y + abajo - radio_punto
    dibujo.ellipse(
        [cx - radio_punto, cy - radio_punto, cx + radio_punto, cy + radio_punto],
        fill=AMARILLO,
    )

    return img


def _muestra_android(frente: Image.Image) -> Image.Image:
    """Simula el icono adaptativo con las formas que usan los launchers.

    Existe porque el PNG del frente NO es lo que se ve: entre el margen que
    agrega flutter_launcher_icons y la mascara del launcher, la marca termina
    bastante mas chica de lo que parece al mirar el archivo suelto.
    """
    lado = 256
    inset = round(lado * 0.16)

    base = Image.new("RGBA", (lado, lado), NEGRO)
    base.alpha_composite(
        frente.resize((lado - inset * 2,) * 2, Image.LANCZOS), (inset, inset)
    )

    formas = []
    for radio in (lado // 2, round(lado * 0.24), round(lado * 0.08)):
        mascara = Image.new("L", (lado, lado), 0)
        ImageDraw.Draw(mascara).rounded_rectangle(
            [0, 0, lado - 1, lado - 1], radius=radio, fill=255
        )
        recortado = base.copy()
        recortado.putalpha(mascara)
        formas.append(recortado)

    aire = 28
    tira = Image.new(
        "RGBA",
        (lado * len(formas) + aire * (len(formas) + 1), lado + aire * 2),
        (60, 60, 64, 255),
    )
    for i, forma in enumerate(formas):
        tira.alpha_composite(forma, (aire + i * (lado + aire), aire))
    return tira


def main() -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)

    # 1. El icono completo: fondo + marca. Lo usan Windows y las versiones
    #    viejas de Android.
    completo = fondo(LADO)
    completo.alpha_composite(marca(LADO, 0.42))
    completo.save(SALIDA / "icono.png")

    # 2. Solo la marca, para el icono adaptativo de Android.
    #
    #    Aca hay dos recortes encadenados y es facil pasarse de chico:
    #    flutter_launcher_icons mete la marca en el 68% central del lienzo
    #    (inset 16% por lado), y ENCIMA el launcher recorta con su forma, que
    #    en el peor caso es un circulo de 66% del lienzo. Con la marca al 30%
    #    quedaba una "M" perdida en un cuadrado negro.
    #
    #    0.58 aca termina siendo ~0.39 del icono final, que es mas o menos lo
    #    que ocupa el dibujo en los iconos del sistema. Mirar
    #    muestra_android.png antes de tocar este numero.
    frente = marca(LADO, 0.58)
    frente.save(SALIDA / "icono_frente.png")

    # 3. Una muestra a los tamanos en los que se va a ver de verdad, para
    #    poder mirarla sin instalar nada.
    tiras = [16, 24, 32, 48, 64, 128, 256]
    aire = 24
    tira = Image.new(
        "RGBA",
        (sum(tiras) + aire * (len(tiras) + 1), max(tiras) + aire * 2),
        (60, 60, 64, 255),
    )
    x = aire
    for t in tiras:
        tira.alpha_composite(
            completo.resize((t, t), Image.LANCZOS),
            (x, (tira.height - t) // 2),
        )
        x += t + aire
    tira.save(SALIDA / "muestra_tamanos.png")

    # 4. Como lo va a recortar Android, que es lo que de verdad se ve en el
    #    telefono y no se parece al PNG de arriba.
    _muestra_android(frente).save(SALIDA / "muestra_android.png")

    print(f"Escrito en {SALIDA}")
    for archivo in sorted(SALIDA.iterdir()):
        print(f"  {archivo.name}")


if __name__ == "__main__":
    main()
