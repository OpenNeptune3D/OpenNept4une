#!/bin/bash

# Find all virtual environments in ~/
venvs=$(find ~ -type d -name "bin" -exec test -f {}/activate \; -print | sed 's|/bin||')

for venv in $venvs; do
    if [[ -f "$venv/bin/activate" ]]; then
        echo "Updating pip in $venv..."
        source "$venv/bin/activate"
        pip install --upgrade pip || echo "Failed to update pip in $venv"
        deactivate
    else
        echo "Skipping $venv: Not a valid virtual environment"
    fi
done

echo "All virtual environments processed!"
