Emulation of the corporate Python base image `corp/hub/python3:3.12`, for tests only (see ../README.md):
`podman build -t localhost/corp/hub/python3:3.12 .` (`--build-arg PY=3.14` for `corp/hub/python3:3.14`).
`corp-test-ca.crt`: test CA to generate (not provided), signer of the fake Nexus certificate.
