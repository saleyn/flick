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

server:
	@PORT=$(if $(port),$(port),8000)
	@echo "Starting HTTP server on port $${PORT}"
	@cd test/js && python3 -m http.server $${PORT}

.PHONY: test minify
