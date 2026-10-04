# Makefile — les quelques commandes utiles.
#
# Rien ici ne touche au dépôt de référence (Msoumaya2019/coran-memoire), qui est
# en LECTURE SEULE. `make guard` vérifie cette règle avant toute poussée.

SHELL := /bin/bash

SCHEME  := Swiftdeepseek
PROJECT := Swiftdeepseek.xcodeproj
TARGET  := Msoumaya2019/Swiftdeepseek
READONLY := Msoumaya2019/coran-memoire

.PHONY: help check-workflows project build test archive ipa guard clean

help:
	@echo "make check-workflows — vérifie les flux GitHub Actions (Node requis)"
	@echo "make project  — génère $(PROJECT) depuis project.yml (XcodeGen)"
	@echo "make build    — compile pour le simulateur"
	@echo "make test     — joue les tests"
	@echo "make ipa      — produit un IPA non signé dans build/"
	@echo "make guard    — refuse de continuer si le dépôt distant n'est pas $(TARGET)"
	@echo "make clean    — supprime les produits de compilation"

# ─────────────────────────────────────────────────────────────────────────────
#  Garde-fou Git.
#
#  Règle non négociable : le dépôt de référence est en LECTURE SEULE, et le seul
#  dépôt inscriptible est $(TARGET). Si `origin` pointe ailleurs — en particulier
#  vers $(READONLY) — on s'arrête net plutôt que de pousser au mauvais endroit.
# ─────────────────────────────────────────────────────────────────────────────
guard:
	@url="$$(git remote get-url origin 2>/dev/null || true)"; \
	if [ -z "$$url" ]; then \
		echo "Aucun dépôt distant « origin ». Ajoute : git remote add origin git@github.com:$(TARGET).git"; \
		exit 1; \
	fi; \
	echo "origin = $$url"; \
	case "$$url" in \
		*$(READONLY)*) \
			echo "REFUS : « origin » pointe vers le dépôt de RÉFÉRENCE ($(READONLY))."; \
			echo "Ce dépôt est en LECTURE SEULE. Rien ne doit y être poussé."; \
			exit 1;; \
		*$(TARGET)*) \
			echo "OK : destination = $(TARGET) (dépôt en écriture).";; \
		*) \
			echo "REFUS : destination inconnue ($$url)."; \
			echo "Attendu : $(TARGET). Vérifie le dépôt distant avant de pousser."; \
			exit 1;; \
	esac

# ─────────────────────────────────────────────────────────────────────────────
#  Contrôle statique des flux, à lancer avant toute poussée.
#
#  Il coûte une seconde ; le flux macOS qu'il protège en coûte quinze. Il exige
#  Node, déjà présent sur les exécuteurs GitHub — c'est pourquoi il tourne aussi
#  en intégration continue, et pas seulement ici.
# ─────────────────────────────────────────────────────────────────────────────
check-workflows:
	@command -v node >/dev/null 2>&1 || { echo "Node absent. Installer : https://nodejs.org"; exit 1; }
	node scripts/verifier-flux.mjs

project:
	@command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen absent. Installer : brew install xcodegen"; exit 1; }
	xcodegen generate --spec project.yml

build: project
	xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'generic/platform=iOS Simulator' \
		CODE_SIGNING_ALLOWED=NO

#  Le simulateur est résolu À L'EXÉCUTION plutôt que nommé en dur.
#  Nommer « iPhone 16 » a déjà fait échouer un flux : le même fichier passait, puis
#  ne passait plus, parce que le contenu de l'image de l'exécuteur avait changé.
#  `xcrun simctl` dit ce qui est réellement installé. Voir SWIFT_MIGRATION.md §9.
test: project
	@DEVICE="$$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $$2; exit}')"; \
	if [ -z "$$DEVICE" ]; then \
		echo "Aucun simulateur iPhone disponible. Appareils vus :"; \
		xcrun simctl list devices available | head -40; \
		exit 1; \
	fi; \
	echo "Simulateur : $$DEVICE"; \
	xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination "id=$$DEVICE" \
		CODE_SIGNING_ALLOWED=NO

archive: project
	xcodebuild archive \
		-project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath build/$(SCHEME).xcarchive \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

ipa: archive
	@rm -rf build/Payload build/$(SCHEME)-unsigned.ipa
	@mkdir -p build/Payload
	@cp -R build/$(SCHEME).xcarchive/Products/Applications/$(SCHEME).app build/Payload/
	@cd build && zip -qry $(SCHEME)-unsigned.ipa Payload
	@echo "IPA : build/$(SCHEME)-unsigned.ipa"

clean:
	rm -rf build DerivedData
