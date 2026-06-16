all: compile

compile test: deps
	@mix $@

deps:
	mix deps.get

clean:
	@mix $@

distclean: clean
	@rm -fr _build

minify:
	npx esbuild priv/flick.js --minify --bundle=false > priv/flick.min.js
	gzip -9 -k -f priv/flick.min.js
	npx esbuild priv/flick-channel.js --minify --bundle=false > priv/flick-channel.min.js
	gzip -9 -k -f priv/flick-channel.min.js

bump-version:
	@CURRENT=$$(grep -oP 'version:\s+"[^"]+"' mix.exs | grep -oP '"\K[^"]+' | head -1); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT | cut -d. -f3); \
	NEW="$${MAJOR}.$${MINOR}.$$((PATCH + 1))"; \
	echo "Bumping version: $${CURRENT} -> $${NEW}"; \
	sed -i "s/\(version: \+\)\"$${CURRENT}\"/\1\"$${NEW}\"/" mix.exs; \
	sed -i 's/\({:flick,[[:space:]]*"~>\)[^"]*/\1 '"$${MAJOR}.$${MINOR}"'/' README.md; \
	echo ""; \
	read -p "Commit this change? [Y/n] " -n 1 -r || true; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]] || [[ -z $$REPLY ]]; then \
	  git commit -am "Bump version to $${NEW}"; \
	fi

server:
	@PORT=$(if $(port),$(port),8000)
	@echo "Starting HTTP server on port $${PORT}"
	@cd test/js && python3 -m http.server $${PORT}

.PHONY: test minify bump-version
