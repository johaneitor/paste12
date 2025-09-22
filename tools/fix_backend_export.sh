#!/bin/bash
echo "== Reparando export en backend (contract_shim & wsgi) =="

# 1. Asegurar que contract_shim.py exporta 'application'
if grep -q -E '^[[:space:]]*application\s*=' contract_shim.py; then
    echo "contract_shim.py: 'application' ya está exportado."
else
    if grep -q -E '^[[:space:]]*app\s*=' contract_shim.py; then
        echo "Agregando 'application = app' a contract_shim.py..."
        # Añade al final la línea de export, precedida de un salto de línea por prolijidad
        printf "\napplication = app\n" >> contract_shim.py
        echo "contract_shim.py: export 'application' añadido."
    else
        echo "ADVERTENCIA: No se encontró variable 'app' en contract_shim.py. Verificar manualmente."
    fi
fi

# 2. Confirmar que wsgi.py importa 'application' explícitamente
if grep -q -E '^from +contract_shim +import +application' wsgi.py; then
    echo "wsgi.py: importación explícita de 'application' ya existe."
else
    if grep -q 'contract_shim' wsgi.py; then
        echo "wsgi.py: actualizando importación de contract_shim..."
        # Reemplaza cualquier import general de contract_shim por import específico de application
        sed -i -E 's/^import +contract_shim.*/from contract_shim import application/' wsgi.py
        # Remueve prefijos 'contract_shim.' de usos de application, si quedaron
        sed -i -E 's/contract_shim\.application/application/g' wsgi.py
        echo "wsgi.py: ahora importa 'application' explícitamente."
    else
        echo "wsgi.py: insertando importación explícita de 'application'..."
        sed -i '1i\from contract_shim import application' wsgi.py
        echo "wsgi.py: línea 'from contract_shim import application' agregada al inicio."
    fi
fi

# 3. Validar sintaxis con py_compile
echo "Verificando sintaxis de contract_shim.py y wsgi.py..."
if python3 -m py_compile contract_shim.py wsgi.py 2>/dev/null; then
    echo "Sintaxis OK ✅"
else
    echo "ERROR: Se encontraron errores de sintaxis. ⚠️"
fi
