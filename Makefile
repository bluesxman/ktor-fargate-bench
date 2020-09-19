zip:
	zip -r -j out/main-js.zip src/js 

update: zip
	aws lambda update-function-code \
  	  --function-name ServerlessExample \
  	  --zip-file fileb://out/main-js.zip
