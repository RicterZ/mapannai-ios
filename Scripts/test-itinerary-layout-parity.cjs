// Verify that the shipped iOS engine is generated from the current Web source.
const fs = require('node:fs')
const vm = require('node:vm')
const assert = require('node:assert/strict')
const crypto = require('node:crypto')
const path = require('node:path')
const root = path.resolve(__dirname, '..')
const web = path.resolve(process.argv[2] || path.join(root, '../mapannai-public'))
const source = fs.readFileSync(path.join(web, 'src/lib/map/itinerary-card-layout.ts'))
assert.equal(crypto.createHash('sha256').update(source).digest('hex'), fs.readFileSync(path.join(root, 'App/Resources/itinerary-card-layout.sha256'), 'utf8').trim())
const esbuild = require(path.join(web, 'node_modules/esbuild'))
const current = esbuild.transformSync(source.toString(), { loader: 'ts', format: 'iife', globalName: 'ItineraryLayout', target: 'es2020' }).code
const load = code => { const context = vm.createContext({}); vm.runInContext(code, context); return context.ItineraryLayout }
const shipped = load(fs.readFileSync(path.join(root, 'App/Resources/itinerary-card-layout.js'), 'utf8'))
const fresh = load(current)
for (const [width, height] of [[393, 700], [1000, 800], [1600, 1100]]) {
  for (const radial of [true, false]) {
    const anchors = Array.from({length: 6}, (_, i) => ({id: `place:${i}`, x: width/2 + (radial ? Math.cos(i)*60 : i*8), y: height/2 + (radial ? Math.sin(i)*70 : i*20), width: 208 + i*8, height: 84+i*12}))
    const bounds = {left:12,top:16,right:width-12,bottom:height-16}
    const paths = [anchors.map(({x,y})=>({x,y}))]
    const actual = shipped.layoutItineraryCards(anchors,bounds,paths)
    assert.equal(JSON.stringify(actual),JSON.stringify(fresh.layoutItineraryCards(anchors,bounds,paths)))
    assert.equal(JSON.stringify(shipped.layoutItineraryCards(anchors,bounds,paths,actual)),JSON.stringify(fresh.layoutItineraryCards(anchors,bounds,paths,actual)))
  }
}
console.log('Web/iOS source hash and linear/radial/phone/tablet layout parity passed')
