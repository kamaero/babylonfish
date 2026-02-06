#!/usr/bin/env python3
import os
import sys
import subprocess

def main():
    icon_path = "icon.png"
    if not os.path.exists(icon_path):
        print(f"Error: {icon_path} not found.")
        print("Please place your icon.png in the project root.")
        return

    # Check for Pillow
    try:
        from PIL import Image
    except ImportError:
        print("Pillow not found. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
        from PIL import Image

    print("Generating icons...")
    
    iconset_dir = "AppIcon.iconset"
    if not os.path.exists(iconset_dir):
        os.makedirs(iconset_dir)

    img = Image.open(icon_path)
    
    # Standard sizes for macOS icons
    sizes = [16, 32, 128, 256, 512]
    
    for size in sizes:
        # Normal
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, f"icon_{size}x{size}.png"))
        
        # Retina (@2x)
        resized_2x = img.resize((size * 2, size * 2), Image.Resampling.LANCZOS)
        resized_2x.save(os.path.join(iconset_dir, f"icon_{size}x{size}@2x.png"))

    # Convert to icns
    print("Converting to icns...")
    subprocess.check_call(["iconutil", "-c", "icns", iconset_dir])
    
    # Move to resources
    dest = "Sources/BabylonFish/Resources/AppIcon.icns"
    if os.path.exists("AppIcon.icns"):
        os.rename("AppIcon.icns", dest)
        print(f"Icon updated at {dest}")
    
    # Cleanup
    import shutil
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)

if __name__ == "__main__":
    main()
