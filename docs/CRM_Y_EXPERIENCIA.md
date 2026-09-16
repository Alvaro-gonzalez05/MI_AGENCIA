# Alta de interesados y experiencia de uso

Cambios preparados para 0.5.0 (14/09/2026).

- Alta desde la pantalla vacía y desde la lista: cliente, interés y evaluación.
- Nombre y CUIT/CUIL obligatorios; contacto, ubicación, unidad, presupuesto,
  financiación y notas opcionales. La validación del CUIT también ocurre en SQL.
- `crear_interesado` guarda persona y oportunidad atómicamente. Una solicitud
  estable permite reintentar sin duplicar; un CUIT existente reutiliza la persona
  sin sobrescribir sus datos ni suscribirla a campañas.
- Consulta BCRA después de guardar. Si falla, se conserva el alta y se puede
  reintentar. Si falla solo el PDF, no se repite la consulta ni el alta.
- PDF generado y archivado en el bucket privado `informes`; se recupera desde
  la ficha. También se puede guardar un informe pendiente de evaluación.
- El semáforo es orientativo: normal para situación 1 sin alertas; revisión
  para 2/3, cheques pagados o mora; alto riesgo para 4-6, impagos o juicio.
  Sin datos o consulta vencida no implica aprobación. Un CUIT nuevo descarta
  la consulta anterior tanto en la ficha como en la vista SQL y la caché.
- Confirmación animada compartida en unidades, gastos, precios, ventas,
  configuración e informes. Carga deshabilitada mientras se guarda.
- Un único acceso a cargar vehículos en el estado vacío.
- Nombre visible **Mi Agencia** y símbolo de auto dentro de una agencia,
  conservando los identificadores de instalación existentes.

## Validación

`scripts/dev.ps1 test` cubre tamaños 360 y 1440, validaciones, errores/reintentos,
persistencia de PDF y generación real del documento. El PDF de prueba se guarda
en `app/build/qa/informe-prueba.pdf`, con datos ficticios para revisión visual.

`node scripts/verificar-crm-remoto.mjs --test-remote` crea dos agencias y usuarios
temporales, comprueba el alta idempotente, conservación del cliente, aislamiento
entre agencias, consulta autenticada y descarga privada del PDF. Elimina solamente
los registros creados en esa ejecución. Requiere `SUPABASE_TOKEN_MI_AGENCIA` en
el entorno y el PDF de prueba generado. No imprime claves ni contraseñas.

En la verificación remota el BCRA respondió 503 tanto desde Supabase como desde
la PC. Se verificó la conservación del alta sin inventar una evaluación. El éxito
contra el proveedor queda pendiente de disponibilidad; las pruebas de interfaz
usan respuestas controladas claramente separadas del servicio real.

Migraciones nuevas: `0014_alta_interesados_informes.sql` y
`0015_bcra_evaluacion_responsable.sql`. Edge Function: `bcra-consulta`.
Se aplicaron al proyecto `zthpwqcoirrpvslambhz` sin modificar datos existentes.

## Paquetes

El workflow manual de instaladores genera artefactos para probar sin modificar
el manifiesto público de actualizaciones. Un tag `v*` sí publica una Release.
Los paquetes fallan si falta la configuración de Supabase, para no distribuir
una demo accidentalmente. Android usa desde la 0.5.0 una firma de distribución
estable guardada en los secretos de GitHub. El APK local se verificó con
`apksigner` y coincide con el certificado respaldado en
`%USERPROFILE%\.mi-agencia`. Como las versiones anteriores usaban firmas de
prueba distintas, hay que desinstalarlas una sola vez antes de instalar 0.5.0;
las versiones siguientes sí se pueden instalar encima.
