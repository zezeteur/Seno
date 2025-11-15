#!/usr/bin/env python3
"""
Script pour créer une icône iOS avec le logo centré sur un fond jaune
"""
from PIL import Image, ImageDraw
import os
import sys

# Couleur de fond (jaune principal)
BACKGROUND_COLOR = (253, 254, 150)  # #FDFE96

# Taille de l'icône iOS (1024x1024 pour la plus grande)
ICON_SIZE = 1024
PADDING_PERCENT = 10  # 10% de padding autour du logo

def create_ios_icon(logo_path, output_path):
    """Crée une icône iOS avec le logo centré sur un fond jaune"""
    
    # Créer l'image de fond
    icon = Image.new('RGB', (ICON_SIZE, ICON_SIZE), BACKGROUND_COLOR)
    
    # Charger le logo
    logo = Image.open(logo_path)
    
    # Calculer la taille du logo avec padding
    padding = int(ICON_SIZE * PADDING_PERCENT / 100)
    max_logo_size = ICON_SIZE - (padding * 2)
    
    # Redimensionner le logo en gardant les proportions
    logo.thumbnail((max_logo_size, max_logo_size), Image.Resampling.LANCZOS)
    
    # Centrer le logo
    x_offset = (ICON_SIZE - logo.width) // 2
    y_offset = (ICON_SIZE - logo.height) // 2
    
    # Coller le logo sur le fond (avec transparence si nécessaire)
    if logo.mode == 'RGBA':
        icon.paste(logo, (x_offset, y_offset), logo)
    else:
        icon.paste(logo, (x_offset, y_offset))
    
    # Sauvegarder
    icon.save(output_path, 'PNG')
    print(f"Icône iOS créée : {output_path}")

if __name__ == '__main__':
    # Chemins
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    logo_path = os.path.join(project_root, 'assets', 'images', 'seno-logo.png')
    output_path = os.path.join(project_root, 'assets', 'images', 'ios-icon.png')
    
    if not os.path.exists(logo_path):
        print(f"Erreur : Le logo n'existe pas à {logo_path}")
        sys.exit(1)
    
    create_ios_icon(logo_path, output_path)
    print("✓ Icône iOS créée avec succès!")

