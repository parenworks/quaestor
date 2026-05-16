# Quaestor - Desktop Ledger Manager

A McCLIM application for managing plain-text .ledger files with a full graphical interface.

## Overview

Quaestor reads, displays, and writes ledger-cli compatible .ledger files. It provides a GUI for account management, transaction entry, balance viewing, and reporting without requiring the user to hand-edit text files. The canonical data format remains the plain-text .ledger file.

## Architecture

### Core Layers

1. **Model Layer** (CLOS + MOP)
   - `ledger` - Top-level container; holds accounts, transactions, and file metadata
   - `account` - Hierarchical account (e.g. `Expenses:Food:Bar`); uses MOP for dynamic slot introspection
   - `transaction` - A dated, cleared/pending entry with postings
   - `posting` - A single line within a transaction (account + amount + optional comment)
   - `commodity` - Currency representation (GBP, USD, etc.)
   - `amount` - Value + commodity, with exact decimal arithmetic

2. **Parser/Writer Layer**
   - Read .ledger files into the model (supports: account directives, transactions, comments, tags, cleared/pending markers, commodity declarations)
   - Write model back to .ledger format preserving alignment and style conventions
   - Round-trip fidelity: reading then writing should produce minimal diff

3. **Configuration Layer**
   - User settings stored in `~/.config/quaestor/config.sexp`
   - Remembers: last opened file, window geometry, account tree expansion state, preferred date format, default commodity
   - Per-file settings (alignment column, account separator)

4. **CLIM Application Layer**
   - McCLIM application frame with multiple panes
   - Presentation types for accounts, transactions, amounts, dates
   - Commands for all user actions
   - Undo/redo via command history

### CLOS Design

All domain objects are CLOS classes. The MOP is used for:
- Dynamic slot access in the account hierarchy (compute inherited properties)
- Custom `print-object` methods for CLIM presentations
- `change-class` for promoting/demoting account types
- Metaclass for `auditable-object` that tracks modification timestamps
- Generic function dispatch for transaction validation rules

```
(defclass ledger ()
  ((file-path :accessor ledger-file-path :initarg :file-path)
   (accounts :accessor ledger-accounts :initform (make-hash-table :test 'equal))
   (transactions :accessor ledger-transactions :initform '())
   (commodities :accessor ledger-commodities :initform '())
   (modified-p :accessor ledger-modified-p :initform nil)))

(defclass account ()
  ((name :accessor account-name :initarg :name)
   (full-path :accessor account-full-path :initarg :full-path)
   (parent :accessor account-parent :initarg :parent :initform nil)
   (children :accessor account-children :initform '())
   (note :accessor account-note :initarg :note :initform nil)
   (type :accessor account-type :initarg :type :initform :expense)))

(defclass transaction ()
  ((date :accessor transaction-date :initarg :date)
   (state :accessor transaction-state :initarg :state :initform :cleared)
   (payee :accessor transaction-payee :initarg :payee)
   (postings :accessor transaction-postings :initarg :postings)
   (comment :accessor transaction-comment :initarg :comment :initform nil)
   (tags :accessor transaction-tags :initform '())))

(defclass posting ()
  ((account :accessor posting-account :initarg :account)
   (amount :accessor posting-amount :initarg :amount :initform nil)
   (comment :accessor posting-comment :initarg :comment :initform nil)))

(defclass amount ()
  ((quantity :accessor amount-quantity :initarg :quantity)
   (commodity :accessor amount-commodity :initarg :commodity)))
```

### MOP Usage

```
(defclass auditable-class (standard-class)
  ()
  (:documentation "Metaclass that adds modification tracking to instances."))

(defmethod validate-superclass ((class auditable-class) (super standard-class))
  t)

(defmethod shared-initialize :after ((instance auditable-object) slot-names &rest initargs)
  (setf (slot-value instance '%last-modified) (get-universal-time)))
```

## User Interface

### Main Frame Layout

```
+------------------------------------------------------------------+
|  [File] [Edit] [View] [Reports] [Help]              Menu Bar     |
+------------------------------------------------------------------+
|  Account Tree    |  Transaction List                              |
|                  |                                                |
|  Assets          |  Date   | State | Payee      | Amount         |
|    Revolut       |  05/14  |  *    | Amazon     | -49.99         |
|      Current     |  05/14  |  *    | Google     | -1.78          |
|  Expenses        |  05/13  |  *    | Western U. | -289.81        |
|    Food          |  ...    |       |            |                |
|      Bar         |                                                |
|      Takeaway    |                                                |
|    Subscriptions |                                                |
|      Codeium     |                                                |
|      ...         |                                                |
|                  +------------------------------------------------+
|                  |  Transaction Detail / Entry Form               |
|                  |                                                |
|                  |  Date: [2026/05/16]  Payee: [_________]        |
|                  |  Account: [Expenses:Food:Bar    ] Amt: [21.70] |
|                  |  Account: [Assets:Revolut:Current]             |
|                  |  [Add Posting] [Save] [Cancel]                 |
+------------------------------------------------------------------+
|  Balance: 2,298.20 GBP          Status: Clean          Ln 1255   |
+------------------------------------------------------------------+
```

### Panes

1. **Account Tree Pane** - Hierarchical view of all accounts; click to filter transactions
2. **Transaction List Pane** - Scrollable list of transactions; filterable by account, date range, payee
3. **Detail Pane** - Shows full transaction detail; doubles as entry/edit form
4. **Status Bar** - Current balance, file modification state, line count

### Key Features

#### Account Management
- Add/rename/delete accounts via right-click context menu or commands
- Drag-and-drop to reparent accounts in the hierarchy
- Account type inference from path prefix (Assets, Expenses, Income, Liabilities, Equity)
- Colour coding by account type

#### Transaction Entry
- Form-based entry with account name completion (fuzzy match)
- Auto-balance: if one posting has no amount, compute it from the others
- Date picker or typed date with format flexibility
- Cleared/pending/unmarked state toggle
- Duplicate detection (same date + payee + amount warns)
- Recurring transaction templates

#### Reporting
- Balance report (equivalent to `ledger bal`)
- Register report (equivalent to `ledger reg`)
- Monthly/weekly spending summary
- Category breakdown (pie chart via CLIM graphics)
- Date range filtering

#### File Operations
- Open/save/save-as
- Auto-save on configurable interval
- Backup before write (keeps .ledger.bak)
- Watch file for external changes (prompt to reload)
- Import from CSV (bank statement import)

### CLIM Presentation Types

```
(define-presentation-type account ())
(define-presentation-type transaction ())
(define-presentation-type amount ())
(define-presentation-type posting ())
(define-presentation-type date-value ())
(define-presentation-type commodity ())
```

These enable:
- Click an account in any context to filter by it
- Click a transaction to view/edit detail
- Drag amounts between postings
- Right-click context menus everywhere

### Commands

```
(define-quaestor-command (com-open-file) ...)
(define-quaestor-command (com-save) ...)
(define-quaestor-command (com-add-transaction) ...)
(define-quaestor-command (com-edit-transaction) ...)
(define-quaestor-command (com-delete-transaction) ...)
(define-quaestor-command (com-add-account) ...)
(define-quaestor-command (com-rename-account) ...)
(define-quaestor-command (com-balance-report) ...)
(define-quaestor-command (com-register-report) ...)
(define-quaestor-command (com-undo) ...)
(define-quaestor-command (com-redo) ...)
(define-quaestor-command (com-settings) ...)
(define-quaestor-command (com-quit) ...)
```

## Configuration

Stored in `~/.config/quaestor/config.sexp`:

```lisp
(:default-file "/home/glenn/Finance/personal.ledger"
 :default-commodity "GBP"
 :commodity-symbol "£"
 :commodity-position :prefix
 :date-format :iso  ; or :eu, :us
 :alignment-column 50
 :auto-save-interval 300  ; seconds, nil to disable
 :window-width 1200
 :window-height 800
 :recent-files ("/home/glenn/Finance/personal.ledger"))
```

## Dependencies

- **McCLIM** - GUI framework
- **local-time** - Date handling
- **cl-ppcre** - Regex for parser
- **alexandria** - Utilities
- **closer-mop** - Portable MOP access

## Build and Run

```sh
# Load via Quicklisp/ASDF
(ql:quickload :quaestor)
(quaestor:main)

# Or from command line via a build script
sbcl --load quaestor.asd --eval '(asdf:load-system :quaestor)' --eval '(quaestor:main)'
```

## File Format Compatibility

Quaestor targets compatibility with ledger-cli and hledger file formats:
- Account directives with notes
- Transaction dates (primary and auxiliary)
- Cleared (*), pending (!), and unmarked states
- Comments (;) on transactions and postings
- Tags in comments
- Commodity declarations
- Amounts with commodity symbols (prefix or suffix)
- Elided amounts (auto-balanced postings)
- Include directives

## Development Phases

### Phase 1: Core Model + Parser
- CLOS model classes
- .ledger file parser (read into model)
- .ledger file writer (model to file)
- Round-trip test suite
- Balance computation

### Phase 2: Basic CLIM UI
- Application frame with panes
- Account tree display
- Transaction list display
- Read-only viewing of an existing .ledger file
- Balance display in status bar

### Phase 3: Editing
- Transaction entry form
- Account management
- Save back to file
- Undo/redo

### Phase 4: Reports and Polish
- Balance and register reports
- Graphical charts
- CSV import
- Settings dialog
- Keyboard shortcuts
- File watching
