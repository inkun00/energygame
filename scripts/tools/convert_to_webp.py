import os
import sys
from PIL import Image

def convert_all_to_webp():
    print("=== Step 1: Converting all assets to WebP ===")
    converted_mapping = {} # "res://...png" -> "res://...webp"
    total_before = 0
    total_after = 0
    count = 0

    for root, dirs, files in os.walk('assets'):
        for f in files:
            ext = f.lower().split('.')[-1]
            if ext in ['png', 'jpg', 'jpeg']:
                src_path = os.path.join(root, f)
                base_name = os.path.splitext(src_path)[0]
                dst_path = base_name + '.webp'
                
                # Res-style path for mapping
                src_res = "res://" + src_path.replace('\\', '/')
                dst_res = "res://" + dst_path.replace('\\', '/')
                
                sz_before = os.path.getsize(src_path)
                total_before += sz_before

                try:
                    with Image.open(src_path) as im:
                        has_alpha = im.mode in ('RGBA', 'LA') or (im.mode == 'P' and 'transparency' in im.info)
                        
                        if has_alpha:
                            im_rgba = im.convert('RGBA')
                            im_rgba.save(dst_path, 'WEBP', quality=90, method=6)
                        else:
                            im_rgb = im.convert('RGB')
                            im_rgb.save(dst_path, 'WEBP', quality=85, method=6)
                            
                    sz_after = os.path.getsize(dst_path)
                    total_after += sz_after
                    count += 1
                    converted_mapping[src_res] = dst_res
                    converted_mapping[src_path.replace('\\', '/')] = dst_path.replace('\\', '/')

                    # Remove old file and its .import file
                    os.remove(src_path)
                    old_import = src_path + '.import'
                    if os.path.exists(old_import):
                        os.remove(old_import)

                    pct = ((sz_before - sz_after) / sz_before) * 100
                    print(f"[{count:3d}] {f:35s} -> {os.path.basename(dst_path):35s} ({sz_after/1024:5.1f} KB, -{pct:4.1f}%)")
                except Exception as e:
                    print(f"Error converting {src_path}: {e}")

    print("==============================================")
    print(f"Converted {count} images to WebP")
    print(f"Total size before: {total_before/1024/1024:6.2f} MB")
    print(f"Total size after:  {total_after/1024/1024:6.2f} MB")
    print(f"Total reduction:   {(total_before - total_after)/1024/1024:6.2f} MB ({(total_before - total_after)/total_before*100:4.1f}% reduction)")

    return converted_mapping

def update_references(mapping):
    print("\n=== Step 2: Updating references in code and scenes ===")
    updated_files = 0
    total_replacements = 0

    target_extensions = ('.gd', '.tscn', '.godot', '.md')
    
    # Sort mapping by key length descending so longer paths match first
    sorted_pairs = sorted(mapping.items(), key=lambda x: len(x[0]), reverse=True)

    for root, dirs, files in os.walk('.'):
        if '.git' in root or '.godot' in root:
            continue
        for f in files:
            if f.endswith(target_extensions):
                file_path = os.path.join(root, f)
                try:
                    with open(file_path, 'r', encoding='utf-8') as fl:
                        content = fl.read()

                    new_content = content
                    file_replacements = 0

                    for src_res, dst_res in sorted_pairs:
                        if src_res in new_content:
                            cnt = new_content.count(src_res)
                            new_content = new_content.replace(src_res, dst_res)
                            file_replacements += cnt

                    if new_content != content:
                        with open(file_path, 'w', encoding='utf-8') as fl:
                            fl.write(new_content)
                        updated_files += 1
                        total_replacements += file_replacements
                        print(f"Updated {file_path}: {file_replacements} references replaced")
                except Exception as e:
                    print(f"Error reading/writing {file_path}: {e}")

    print(f"Successfully updated {updated_files} files with {total_replacements} replacements.")

if __name__ == '__main__':
    mapping = convert_all_to_webp()
    update_references(mapping)
