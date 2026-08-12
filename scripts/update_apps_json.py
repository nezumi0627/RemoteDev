import json
import sys
import os
from datetime import datetime

BUNDLE_ID = "com.nezumi0627.remotedev"

def update_apps_json(version, build, download_url, size_bytes, sha256):
    file_path = 'docs/apps.json'

    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    app = next((a for a in data['apps'] if a['bundleIdentifier'] == BUNDLE_ID), None)
    if not app:
        print(f"Error: App with bundleIdentifier '{BUNDLE_ID}' not found in JSON.")
        return

    version_entry = next((v for v in app['versions'] if v['version'] == version and str(v.get('build', '')) == str(build)), None)

    new_version = {
        "version": version,
        "build": int(build),
        "date": datetime.now().strftime("%Y-%m-%d"),
        "downloadURL": download_url,
        "size": int(size_bytes),
        "sha256": sha256,
        "localizedDescription": f"Build {build} - 自動ビルドによる更新"
    }

    if version_entry:
        app['versions'].remove(version_entry)

    app['versions'].insert(0, new_version)
    app['versions'] = app['versions'][:5]

    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f"Successfully updated apps.json to version {version} (Build {build})")

if __name__ == "__main__":
    if len(sys.argv) < 6:
        print("Usage: python update_apps_json.py <version> <build> <url> <size> <sha256>")
        sys.exit(1)

    update_apps_json(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
