# Quaestor - McCLIM Ledger Manager
# Build and run recipes

default_file := env("QUAESTOR_LEDGER", "~/Finance/personal.ledger")
install_dir := "/usr/local/bin"

# Build with SBCL (default, compressed image)
build:
    @echo "Building Quaestor with SBCL..."
    sbcl --non-interactive --load build.lisp
    @echo "Done: bin/quaestor"

# Build with ECL (native compiled)
build-ecl:
    @echo "Building Quaestor with ECL..."
    ecl --load build.lisp
    @echo "Done: bin/quaestor"

# Run from source (no build needed)
run *ARGS:
    sbcl --non-interactive \
         --eval '(require :asdf)' \
         --eval '(asdf:load-system :quaestor)' \
         --eval '(quaestor:main :file "{{default_file}}")' \
         -- {{ARGS}}

# Run the built binary
run-bin *ARGS:
    ./bin/quaestor {{ARGS}}

# Install to /usr/local/bin (requires sudo)
install: build
    @echo "Installing to {{install_dir}}/quaestor..."
    sudo install -m 755 bin/quaestor {{install_dir}}/quaestor
    @echo "Installed."

# Uninstall
uninstall:
    sudo rm -f {{install_dir}}/quaestor

# Run tests
test:
    sbcl --non-interactive \
         --eval '(require :asdf)' \
         --eval '(asdf:test-system :quaestor)'

# Load into a REPL for interactive development
repl:
    sbcl --eval '(require :asdf)' \
         --eval '(asdf:load-system :quaestor)' \
         --eval '(in-package :quaestor)'

# Parse a ledger file and print balance report (CLI mode)
balance file=default_file:
    sbcl --non-interactive \
         --eval '(require :asdf)' \
         --eval '(asdf:load-system :quaestor)' \
         --eval '(let ((l (quaestor::parse-ledger-file "{{file}}"))) (dolist (entry (quaestor::balance-report l)) (format t "~40A ~A~%" (car entry) (quaestor::format-amount (cdr entry)))))'

# Clean build artifacts
clean:
    rm -rf bin/
