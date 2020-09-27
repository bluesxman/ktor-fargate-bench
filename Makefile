zip:
	rm -f out/main-js.zip
	npm prune --production
	zip -r -j out/main-js.zip src/js
	zip -r -g out/main-js.zip node_modules

update: zip
	aws lambda update-function-code \
  	  --function-name ServerlessExample \
  	  --zip-file fileb://out/main-js.zip
