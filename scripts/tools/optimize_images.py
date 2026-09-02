import os
import sys
from PIL import Image

def optimize_image(file_path):
    orig_size = os.path.getsize(file_path)
    rel_path = os.path.relpath(file_path, 'assets').replace('\\', '/')
    ext = file_path.lower().split('.')[-1]

    # Skip kenney vector or ui pack if already small
    if 'kenney_' in rel_path and orig_size < 150 * 1024:
        return orig_size, orig_size, False

    try:
        with Image.open(file_path) as im:
            orig_w, orig_h = im.size
            im_format = im.format

            # Determine maximum bounding dimension
            if 'story' in rel_path or 'kingdom' in rel_path or 'maps' in rel_path:
                max_w, max_h = 1280, 720
            elif 'sprites' in rel_path:
                # Spritesheets with 4 horizontal frames
                max_w, max_h = 1440, 720
            elif 'buildings' in rel_path or 'items' in rel_path:
                max_w, max_h = 512, 512
            elif 'characters' in rel_path:
                max_w, max_h = 640, 768
            elif 'images' in rel_path:
                max_w, max_h = 1024, 768
            else:
                max_w, max_h = 800, 800

            # Resize if exceeds target bounds
            scale = min(max_w / orig_w, max_h / orig_h)
            new_im = im.copy()
            if scale < 1.0:
                new_w = max(1, int(round(orig_w * scale)))
                new_h = max(1, int(round(orig_h * scale)))
                new_im = new_im.resize((new_w, new_h), Image.Resampling.LANCZOS)

            temp_path = file_path + ".tmp"
            if ext in ['jpg', 'jpeg']:
                new_im.convert('RGB').save(temp_path, 'JPEG', quality=85, optimize=True)
            elif ext == 'png':
                new_im.save(temp_path, 'PNG', optimize=True)
            else:
                return orig_size, orig_size, False

            new_size = os.path.getsize(temp_path)
            # Only replace if new size is smaller
            if new_size < orig_size:
                os.replace(temp_path, file_path)
                return orig_size, new_size, True
            else:
                if os.path.exists(temp_path):
                    os.remove(temp_path)
                return orig_size, orig_size, False
    except Exception as e:
        print(f"Error optimizing {file_path}: {e}")
        return orig_size, orig_size, False

def main():
    print("=== Starting Game Image Optimization ===")
    
    # 1. Remove 9 unreferenced non-alpha _move.png duplicates
    sprites_dir = os.path.join('assets', 'characters', 'eco_roster', 'sprites')
    unused_move_files = [
        'bear_pongi_move.png',
        'captain_eco_move.png',
        'earth_turtle_tori_move.png',
        'lightning_bird_pika_move.png',
        'mushroom_cat_momo_move.png',
        'recycle_raccoon_ringo_move.png',
        'solar_fox_sol_move.png',
        'water_popo_move.png',
        'wind_rabbit_bori_move.png'
    ]
    deleted_bytes = 0
    for filename in unused_move_files:
        p = os.path.join(sprites_dir, filename)
        p_import = p + ".import"
        if os.path.exists(p):
            sz = os.path.getsize(p)
            deleted_bytes += sz
            os.remove(p)
            print(f"Removed unused duplicate: {filename} ({sz/1024/1024:.2f} MB)")
        if os.path.exists(p_import):
            os.remove(p_import)

    # 2. Remove _downloads zip files
    downloads_dir = os.path.join('assets', 'open_source', '_downloads')
    if os.path.exists(downloads_dir):
        import shutil
        for item in os.listdir(downloads_dir):
            item_p = os.path.join(downloads_dir, item)
            if item.endswith('.zip'):
                sz = os.path.getsize(item_p)
                deleted_bytes += sz
                os.remove(item_p)
                print(f"Removed redundant download archive: {item} ({sz/1024/1024:.2f} MB)")

    # 3. Optimize remaining images
    total_orig = 0
    total_new = 0
    opt_count = 0

    for root, dirs, files in os.walk('assets'):
        for f in files:
            ext = f.lower().split('.')[-1]
            if ext in ['png', 'jpg', 'jpeg']:
                p = os.path.join(root, f)
                orig_sz, new_sz, modified = optimize_image(p)
                total_orig += orig_sz
                total_new += new_sz
                if modified:
                    opt_count += 1
                    saved_kb = (orig_sz - new_sz) / 1024
                    pct = ((orig_sz - new_sz) / orig_sz) * 100
                    print(f"Optimized [{opt_count:2d}] {os.path.relpath(p, 'assets'):50s} -> {new_sz/1024:6.1f} KB (-{pct:4.1f}%, saved {saved_kb:6.1f} KB)")

    print("========================================")
    print(f"Total images optimized: {opt_count}")
    print(f"Unused files deleted: {deleted_bytes / 1024 / 1024:.2f} MB")
    print(f"Image reduction: {total_orig / 1024 / 1024:.2f} MB -> {total_new / 1024 / 1024:.2f} MB")
    total_saved = deleted_bytes + (total_orig - total_new)
    print(f"TOTAL SAVINGS: {total_saved / 1024 / 1024:.2f} MB ({(total_saved / (total_orig + deleted_bytes)) * 100:.1f}% reduction)")

if __name__ == '__main__':
    main()
