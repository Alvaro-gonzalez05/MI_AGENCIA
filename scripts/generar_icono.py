# Mi Agencia: agencia con auto, generado a todas las resoluciones.
from pathlib import Path

from PIL import Image, ImageDraw

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
    """Silueta de una agencia: techo, portón abierto y auto en el centro."""
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    # Techo y columnas: trazos gruesos que resisten un icono de 32 px.
    d.line([(130, 390), (512, 135), (894, 390)], fill=AMARILLO, width=65, joint="curve")
    d.rounded_rectangle((162, 365, 223, 838), radius=22, fill=AMARILLO)
    d.rounded_rectangle((801, 365, 862, 838), radius=22, fill=AMARILLO)
    d.rounded_rectangle((303, 366, 721, 408), radius=20, fill=AMARILLO)
    # Techo del auto, parabrisas calado y carrocería.
    d.polygon([(306, 607), (367, 466), (657, 466), (718, 607)], fill=AMARILLO)
    d.polygon([(366, 595), (401, 516), (623, 516), (658, 595)], fill=NEGRO)
    d.rounded_rectangle((278, 582, 746, 760), radius=49, fill=AMARILLO)
    d.rounded_rectangle((301, 722, 363, 824), radius=20, fill=AMARILLO)
    d.rounded_rectangle((661, 722, 723, 824), radius=20, fill=AMARILLO)
    d.rounded_rectangle((318, 630, 400, 669), radius=17, fill=NEGRO)
    d.rounded_rectangle((624, 630, 706, 669), radius=17, fill=NEGRO)
    d.rounded_rectangle((453, 695, 571, 715), radius=10, fill=NEGRO)
    # La marca ocupa 76% del lienzo base. Centrada en la zona segura.
    escala = alto_relativo / .76
    tam = round(lado * escala)
    img = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    img.alpha_composite(canvas.resize((tam, tam), Image.LANCZOS), ((lado-tam)//2, (lado-tam)//2))
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
    completo.alpha_composite(marca(LADO, 0.67))
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
    frente = marca(LADO, 0.72)
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
