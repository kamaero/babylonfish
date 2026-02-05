import sys
from PIL import Image

def process_icon(input_path, output_path):
    try:
        img = Image.open(input_path).convert("RGBA")
        
        # Get the bounding box of the non-zero alpha pixels
        bbox = img.getbbox()
        if not bbox:
            print("Image is completely transparent!")
            return

        # Crop to the content
        cropped = img.crop(bbox)
        
        # Determine the size of the cropped content
        content_width, content_height = cropped.size
        
        # We want to scale this content to fit nicely in a 1024x1024 square
        # Let's say we want 10% padding
        target_size = 1024
        padding = int(target_size * 0.1)
        max_content_size = target_size - (2 * padding)
        
        # Calculate scale factor
        scale = min(max_content_size / content_width, max_content_size / content_height)
        
        new_width = int(content_width * scale)
        new_height = int(content_height * scale)
        
        # Resize the content
        # Resampling.LANCZOS is high quality
        resized_content = cropped.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Create a new blank 1024x1024 image
        new_img = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
        
        # Center the content
        x_offset = (target_size - new_width) // 2
        y_offset = (target_size - new_height) // 2
        
        new_img.paste(resized_content, (x_offset, y_offset), resized_content)
        
        new_img.save(output_path)
        print(f"Icon processed and saved to {output_path}")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python process_icon.py <input_icon>")
    else:
        process_icon(sys.argv[1], "icon_large.png")
