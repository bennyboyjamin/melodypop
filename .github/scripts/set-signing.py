#!/usr/bin/env python3
"""Switches the MelodyPop app target (only) to manual App Store signing for a CI build.

Signing settings are written into the app target's build configurations instead of being
passed on the xcodebuild command line, because command-line settings also hit the
MelodyPopKit Swift package, which can't take a provisioning profile.

Usage: set-signing.py PROJECT.pbxproj  (reads TEAM, BUNDLE_ID, PROFILE_NAME, VER, BUILD from the environment)
"""
import os
import re
import sys

path = sys.argv[1]
text = open(path).read()
env = os.environ
wanted = {
    "DEVELOPMENT_TEAM": env["TEAM"],
    "CODE_SIGN_STYLE": "Manual",
    '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"': '"Apple Distribution"',
    "CODE_SIGN_IDENTITY": '"Apple Distribution"',
    "PROVISIONING_PROFILE_SPECIFIER": '"%s"' % env["PROFILE_NAME"],
    "PRODUCT_BUNDLE_IDENTIFIER": env["BUNDLE_ID"],
    "MARKETING_VERSION": env["VER"],
    "CURRENT_PROJECT_VERSION": env["BUILD"],
}

# The app target's configurations are the ones with the app's base bundle ID.
block_re = re.compile(r"(buildSettings = \{\n)(.*?)(\n\t\t\t\};)", re.S)
changed = 0


def fix(m):
    global changed
    body = m.group(2)
    if "PRODUCT_BUNDLE_IDENTIFIER = com.saystudios.melodypop;" not in body:
        return m.group(0)
    lines = [l for l in body.split("\n")
             if not any(re.match(r"\s*%s = " % re.escape(k), l) for k in wanted)]
    lines += ["\t\t\t\t%s = %s;" % (k, v) for k, v in wanted.items()]
    changed += 1
    return m.group(1) + "\n".join(lines) + m.group(3)


text = block_re.sub(fix, text)
if changed != 2:
    sys.exit("Expected 2 app build configurations, changed %d" % changed)
open(path, "w").write(text)
print("App target set to manual signing with profile %r, version %s (%s)" % (env["PROFILE_NAME"], env["VER"], env["BUILD"]))
