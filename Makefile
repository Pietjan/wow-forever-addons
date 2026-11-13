# Change these variables as necessary.
addons_dir = addons
dist_dir = dist
github_repo = Pietjan/wow-forever-addons
# The repo that copies addons into the game (mine is not public; see README).
manager_path = ../wow-addons

# An addon's version is the "## Version:" line of its .toc.
version = $(shell sed -n 's/^\#\# Version:[[:space:]]*//p' "$(addons_dir)/$*/$*.toc" 2>/dev/null | tr -d '\r')
# A release is the tag <Addon>-v<version> with <Addon>-<version>.zip attached.
tag = $*-v$(version)
zip = $(dist_dir)/$*-$(version).zip

# ==================================================================================== #
# HELPERS
# ==================================================================================== #

## help: print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' | sed -e 's/^/ /'

.PHONY: confirm
confirm:
	@echo -n 'Are you sure? [y/N] ' && read ans && [ $${ans:-N} = y ]

.PHONY: no-dirty
no-dirty:
	@test -z "$(shell git status --porcelain --untracked-files=no)" || { echo 'There are uncommitted changes.'; exit 1; }

# The commit a release is cut from has to be on GitHub already.
.PHONY: no-unpushed
no-unpushed:
	@git fetch --quiet origin
	@test "$$(git rev-parse HEAD)" = "$$(git rev-parse '@{upstream}')" || { echo 'HEAD is not what is on GitHub: push (or pull) first.'; exit 1; }

# ==================================================================================== #
# QUALITY CONTROL
# ==================================================================================== #

## audit: compile every addon and look for locals used before definition
.PHONY: audit
audit:
	@python3 -I scripts/check-lua.py

# ==================================================================================== #
# DEVELOPMENT
# ==================================================================================== #

## guides: fetch the RestedXP and WoW-Pro guide files that ForeverGuide reads
.PHONY: guides
guides:
	@python3 -I scripts/guides.py

## install: run the checks, then let ../wow-addons copy the addons into the game
.PHONY: install
install:
	@test -f "$(manager_path)/Makefile" || { echo "No $(manager_path): copy the folders under $(addons_dir)/ into the game's Interface/AddOns by hand."; exit 1; }
	@$(MAKE) --no-print-directory -C "$(manager_path)" install

# ==================================================================================== #
# OPERATIONS
# ==================================================================================== #

## versions: list every addon with its version and whether that version is released
.PHONY: versions
versions:
	@git fetch --quiet --tags origin
	@for toc in $(addons_dir)/*/*.toc; do \
		name=$$(basename "$$toc" .toc); \
		version=$$(sed -n 's/^## Version:[[:space:]]*//p' "$$toc" | tr -d '\r'); \
		if git rev-parse -q --verify "refs/tags/$$name-v$$version" >/dev/null; then state=released; else state=-; fi; \
		echo "$$name:$$version:$$state"; \
	done | column -t -s ':'

## site: write docs/index.html, the page with every addon and its download
.PHONY: site
site:
	@git fetch --quiet --tags origin
	@python3 -I scripts/site.py "$(github_repo)"

## package/<addon>: zip the committed files of one addon into dist/
package/%: audit
	@test -n "$(version)" || { echo "No addon '$*' with a version in $(addons_dir)/$*/$*.toc."; exit 1; }
	@git rev-parse -q --verify "HEAD:$(addons_dir)/$*" >/dev/null || { echo "$* is not committed yet."; exit 1; }
	@test -z "$$(git status --porcelain -- "$(addons_dir)/$*")" || { echo "$* has uncommitted changes; a release holds committed files only."; exit 1; }
	@mkdir -p "$(dist_dir)"
	@git archive --format=zip --output="$(zip)" "HEAD:$(addons_dir)" "$*"
	@echo "$(zip)"

## release/<addon>: publish one addon's current version as a GitHub release
release/%: no-unpushed package/%
	@if git ls-remote --exit-code --tags origin "refs/tags/$(tag)" >/dev/null; then \
		echo "$(tag) is already released: raise the version in $(addons_dir)/$*/$*.toc first."; exit 1; fi
	@previous=$$(git tag --list '$*-v*' --sort=-creatordate | head -1); \
	{ \
		echo "Unzip into the game's \`Interface/AddOns\` folder, so that it holds a \`$*\` folder, and \`/reload\`."; \
		if [ -n "$$(git status --porcelain --ignored -- "$(addons_dir)/$*" | grep '^!!')" ]; then \
			echo; echo "Files this addon needs that are kept out of git are not in the zip; see the README."; fi; \
		echo; echo "Changes$${previous:+ since $$previous}:"; echo; \
		git log --format='- %s' $${previous:+$$previous..}HEAD -- "$(addons_dir)/$*"; \
	} > "$(dist_dir)/$(tag).md"
	@echo "Release $(tag) of $(github_repo), from commit $$(git rev-parse --short HEAD), with $(zip) and these notes:"; echo
	@sed 's/^/    /' "$(dist_dir)/$(tag).md"; echo
	@$(MAKE) --no-print-directory confirm
	@gh release create "$(tag)" "$(zip)" --repo "$(github_repo)" --target "$$(git rev-parse HEAD)" \
		--title "$* $(version)" --notes-file "$(dist_dir)/$(tag).md"
	@echo "Run 'make site' and commit docs/index.html so the page links to $(tag)."
