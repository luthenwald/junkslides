#!/bin/sh
# Installs junkslides under a prefix, or removes it again.
#
#    ./install.sh [--prefix <folder>]              (the default is ~/.local)
#    ./install.sh --uninstall [--prefix <folder>]
#
# It builds the editor and the server once, copies the build to
# <prefix>/lib/junkslides and writes the command <prefix>/bin/junkslides.
# Nothing else is touched. Erlang is still needed to run the command.

set -eu

prefix="${HOME}/.local"
uninstall=no

usage() {
   sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
   case "$1" in
      --prefix)
         [ $# -ge 2 ] || { echo "--prefix needs a folder." >&2; exit 1; }
         prefix="$2"
         shift 2
         ;;
      --prefix=*)
         prefix="${1#--prefix=}"
         shift
         ;;
      --uninstall)
         uninstall=yes
         shift
         ;;
      -h | --help)
         usage
         exit 0
         ;;
      *)
         echo "Unknown option: $1" >&2
         usage >&2
         exit 1
         ;;
   esac
done

[ -n "$prefix" ] || { echo "The prefix is empty." >&2; exit 1; }

# An absolute prefix, since the command is called from other folders.
case "$prefix" in
   /*) ;;
   *) prefix="$(pwd)/$prefix" ;;
esac

lib="$prefix/lib/junkslides"
bin="$prefix/bin/junkslides"

if [ "$uninstall" = yes ]; then
   rm -rf "$lib"
   rm -f "$bin"
   echo "Removed $lib"
   echo "Removed $bin"
   echo "The editor's view settings, if any, are in ~/.config/junkslides."
   exit 0
fi

need() {
   command -v "$1" > /dev/null 2>&1 || {
      echo "$1 was not found. $2" >&2
      exit 1
   }
}

need gleam "Install Gleam first: https://gleam.run/getting-started/installing/"
need erl "Install Erlang first; Gleam's page above says how."

root="$(cd "$(dirname "$0")" && pwd)"
[ -f "$root/server/gleam.toml" ] && [ -f "$root/client/gleam.toml" ] || {
   echo "Run this script from a copy of the junkslides project." >&2
   exit 1
}

echo "Building the editor..."
rm -rf "$root/server/priv/static"
(
   cd "$root/client"
   gleam run -m lustre/dev build --outdir=../server/priv/static --no-html --minify > /dev/null
)

echo "Building junkslides..."
(
   cd "$root/server"
   gleam export erlang-shipment > /dev/null
)

shipment="$root/server/build/erlang-shipment"
[ -x "$shipment/entrypoint.sh" ] || {
   echo "The build did not give $shipment/entrypoint.sh." >&2
   exit 1
}

mkdir -p "$prefix/lib" "$prefix/bin"
rm -rf "$lib"
cp -R "$shipment" "$lib"

cat > "$bin" << EOF
#!/bin/sh
exec "$lib/entrypoint.sh" run "\$@"
EOF
chmod +x "$bin"

echo "Installed $lib"
echo "Installed $bin"

case ":${PATH}:" in
   *":$prefix/bin:"*) ;;
   *) echo "$prefix/bin is not on your PATH; add it, or call the command by its full path." ;;
esac
