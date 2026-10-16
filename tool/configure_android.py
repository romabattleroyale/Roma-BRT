#!/usr/bin/env python3
"""Apply the Android native settings required by SENTINEL ONE plugins.

Run after `flutter create --platforms=android --org com.sentinelone .`.
Shared by GitHub Actions and Codemagic so their APK builds stay equivalent.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android" / "app"


def configure_gradle() -> None:
    kotlin = ANDROID / "build.gradle.kts"
    groovy = ANDROID / "build.gradle"

    if kotlin.exists():
        path = kotlin
        source = path.read_text(encoding="utf-8")
        if "pickFirsts" not in source:
            if "android {" not in source:
                raise RuntimeError(f"Missing android block in {path}")
            source = source.replace(
                "android {",
                'android {\n    packaging { jniLibs { pickFirsts += setOf("lib/**/libc++_shared.so") } }',
                1,
            )
        if "isCoreLibraryDesugaringEnabled" not in source:
            if "compileOptions {" not in source:
                raise RuntimeError(f"Missing compileOptions block in {path}")
            source = source.replace(
                "compileOptions {",
                "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
                1,
            )
        if "coreLibraryDesugaring(" not in source:
            source += (
                '\n\ndependencies {\n'
                '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
                '}\n'
            )
        path.write_text(source, encoding="utf-8")
        return

    if groovy.exists():
        path = groovy
        source = path.read_text(encoding="utf-8")
        if "pickFirst" not in source:
            if "android {" not in source:
                raise RuntimeError(f"Missing android block in {path}")
            source = source.replace(
                "android {",
                "android {\n    packagingOptions { pickFirst 'lib/**/libc++_shared.so' }",
                1,
            )
        if "coreLibraryDesugaringEnabled" not in source:
            if "compileOptions {" not in source:
                raise RuntimeError(f"Missing compileOptions block in {path}")
            source = source.replace(
                "compileOptions {",
                "compileOptions {\n        coreLibraryDesugaringEnabled true",
                1,
            )
        if "coreLibraryDesugaring " not in source:
            source += (
                "\n\ndependencies {\n"
                "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
                "}\n"
            )
        path.write_text(source, encoding="utf-8")
        return

    raise FileNotFoundError("Flutter did not generate android/app/build.gradle[.kts]")


def configure_manifest() -> None:
    manifest = ANDROID / "src" / "main" / "AndroidManifest.xml"
    source = manifest.read_text(encoding="utf-8")
    for permission in ("android.permission.INTERNET", "android.permission.CAMERA"):
        declaration = f'<uses-permission android:name="{permission}"'
        if declaration in source:
            continue
        application_tag = "    <application"
        if application_tag not in source:
            raise RuntimeError(f"Missing application tag in {manifest}")
        source = source.replace(
            application_tag,
            f'    <uses-permission android:name="{permission}" />\n{application_tag}',
            1,
        )
    manifest.write_text(source, encoding="utf-8")


def configure_notification_icon() -> None:
    drawable = ANDROID / "src" / "main" / "res" / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    icon = drawable / "ic_stat_sentinel.xml"
    icon.write_text(
        """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M12,1 L3,5 V11 C3,16.5 6.8,21.3 12,23 C17.2,21.3 21,16.5 21,11 V5 Z M10.5,15.5 L7.5,12.5 L8.9,11.1 L10.5,12.7 L15.5,7.7 L16.9,9.1 Z"/>
</vector>
""",
        encoding="utf-8",
    )


def main() -> None:
    configure_gradle()
    configure_manifest()
    configure_notification_icon()
    print("Configured Android desugaring, native libraries, camera/network permissions, and notification icon.")


if __name__ == "__main__":
    main()
