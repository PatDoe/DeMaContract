const fs = require('fs')
const path = require('path');

function saveToJson(name, date) {
    let json;

    const uplevelDir = path.resolve(__dirname, '..');
    const file = path.join(uplevelDir, `bin/contracts/address.json`);

    const fileDir = path.resolve(file, '..');
    
    if(!fs.existsSync(fileDir)) {
        console.log(`Not exist ${fileDir}`);
        fs.mkdirSync(fileDir, {recursive:true});
        console.log(`Make ${fileDir} success!`);
    }

    try {
        const jsonStringFromRead = fs.readFileSync(file);
        json = JSON.parse(jsonStringFromRead);
    } catch(err) {
        console.log(err)
        json = {}
    }

    json[name] = date;

    const jsonStringToWrite = JSON.stringify(json, null, 2);
    fs.writeFileSync(file, jsonStringToWrite,{ flag:'w'});
}

module.exports = saveToJson;