"""Install the pinned, checksum-verified bd binary locally; no global hooks."""

import hashlib
import platform
import subprocess
import tarfile
import tempfile
from pathlib import Path

VERSION = "1.3.0"
CHECKSUMS = {
    ("Darwin", "arm64"): ("darwin_arm64", "7cc77367d0b84c50243a1108bc1f73648699211257d414b917540bf868e6bb85"),
    ("Darwin", "x86_64"): ("darwin_amd64", "dfd8a6918bc2a58a0dbc727f7e4039766e323dfa15e4ccab250d640851e290d5"),
    ("Linux", "aarch64"): ("linux_arm64", "4ce9446a68edc13202b76c84a47d66fb3dad2787b6464c9522a108faf9c1c608"),
    ("Linux", "x86_64"): ("linux_amd64", "2f92b904ecf35b607e44dc5c39229173af69c54f1183e8d709f1773540cdcf3b"),
}


def install() -> None:
    target, digest = CHECKSUMS[(platform.system(), platform.machine())]
    name = f"beads_{VERSION}_{target}.tar.gz"
    root = Path(__file__).resolve().parents[1]
    output = root / ".orchestration" / "bin"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="crm-beads-") as temporary:
        subprocess.run([
            "gh", "release", "download", f"v{VERSION}", "--repo", "gastownhall/beads",
            "--pattern", name, "--dir", temporary,
        ], check=True)
        archive = Path(temporary) / name
        if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
            raise ValueError("Release checksum mismatch; the installed binary was not replaced.")
        with tarfile.open(archive) as package:
            binaries = [m for m in package.getmembers() if Path(m.name).name == "bd" and m.isfile()]
            if len(binaries) != 1:
                raise ValueError("Release must contain exactly one regular bd binary.")
            # Extract only the binary's bytes; no archive paths or symlinks are used.
            staging = output / "bd.download"
            staging.write_bytes(package.extractfile(binaries[0]).read())
            staging.chmod(0o755)
            staging.replace(output / "bd")
    subprocess.run([str(output / "bd"), "version"], check=True)
    print(f"Installed {output / 'bd'}; global CLI and agent hooks unchanged.")


if __name__ == "__main__":
    install()
