#!/usr/bin/node
const fs = require('fs')
const path = require('path')
const net = require('net')
const util = require('util')
const cp = require('child_process')
const Influx = require('influx')
const {performance} = require('perf_hooks')

const BASEDIR = '/srv/minecraft/'
const REQUEST_PACKET = Buffer.from('060000000000010100', 'hex') // version=0 address='' port=0 next_state=1, request

const influx = new Influx.InfluxDB({
  host: '127.0.0.1',
  database: 'minecraft',
  schema: [{
    measurement: 'server-status',
    fields: {
      max: Influx.FieldType.INTEGER,
      online: Influx.FieldType.INTEGER,
      ping: Influx.FieldType.FLOAT,
      pid: Influx.FieldType.INTEGER,
      memUsed: Influx.FieldType.INTEGER
    },
    tags: [
      'server'
    ]
  }]
})

function readServerProperties(server) {
  const file = path.resolve(BASEDIR, server, 'server.properties')
  const lines = fs.readFileSync(file, 'utf8').split('\n')
  const serverProps = {}
  for (const line of lines) {
    if (!line || line.startsWith('#')) continue
    const i = line.indexOf('=')
    const key = line.slice(0, i)
    let value = line.slice(i + 1)
    if (/^\d+$/.test(value)) value = Number(value)
    else if (/^(true|false)$/.test(value)) value = value === 'true'
    serverProps[key] = value
  }
  return serverProps
}

function fetch(server, cb) {
  const serverProps = readServerProperties(server)
  const port = serverProps['server-port']
  const conn = net.createConnection({port}, () => {
    // console.log('Connected to ' + server)
    conn.write(REQUEST_PACKET)
  })
  conn.setNoDelay(true)
  conn.setTimeout(3000)
  let pingSent
  const result = {server}
  conn.on('data', data => {
    const pb = {off: 0, buf: data}
    const packet = readPacket(pb)
    switch (packet.type) {
      case 'response': {
        result.max = packet.data.players.max
        result.online = packet.data.players.online
        pingSent = performance.now()
	conn.write(Buffer.from('09010123456789abcdef', 'hex'))
	break
      }
      case 'pong': {
        const rtt = performance.now() - pingSent
        if (packet.data.toString('hex') === '0123456789abcdef') {
	  result.ping = rtt
        }
	cb(null, result)
        conn.destroy()
        break
      }
    }
  })
  conn.on('error', e => {
    cb(e)
  })
  conn.on('end', () => {
    // console.log('Disconnected from ' + server)
  })
}


function readPacket(pb) {
  const length = readVarInt(pb)
  const pb2 = {off: 0, buf: pb.buf.slice(pb.off, pb.off + length)}
  const id = readVarInt(pb2)
  switch (id) {
    case 0: return readResponse(pb2)
    case 1: return readPong(pb2)
  }
}

function readResponse(pb) {
  const strlen = readVarInt(pb)
  const json = pb.buf.slice(pb.off, pb.off + strlen).toString('utf8')
  return {type: 'response', data: JSON.parse(json)}
}

function readPong(pb) {
  return {type: 'pong', data: pb.buf.slice(pb.off)}
}

function readVarInt(pb) {
  let nRead = 0
  let result = 0
  let b
  do {
    b = pb.buf[pb.off++]
    result |= (b & 0x7f) << (7 * nRead++)
  } while ((b & 0x80) !== 0)
  return result
}

function meminfo(server) {
  const pid = Number(cp.spawnSync('pidof', [server], {encoding: 'utf8'}).stdout.trim())
  const heapInfo = cp.spawnSync('jcmd', [pid, 'GC.heap_info'], {encoding: 'utf8'}).stdout
  const match = heapInfo.match(/used (\d+)K/)
  if (match) return {pid, memUsed: Number(match[1]) * 1024}
  return {pid} 
}

const ps = []
for(const server of fs.readdirSync(BASEDIR)) {
  try {
    const dir = path.resolve(BASEDIR, server)
    const stats = fs.statSync(dir)
    if (!stats.isDirectory()) continue
    const props = path.resolve(dir, 'server.properties')
    if (!fs.existsSync(props)) continue
    const mem = meminfo(server)
    ps.push(util.promisify(fetch)(server).then(d => {
      for (const k in mem) d[k] = mem[k]
      return d
    }).catch(e => {
      //console.error('Error connecting to ' + server + ':', e)
    }))
  } catch(e) {
    console.error(e)
  }
}

Promise.all(ps).then(data => {
  influx.writePoints(data.filter(Boolean).map(d => ({measurement: 'server-status', tags: {server: d.server}, fields: {online: d.online, max: d.max, ping: d.ping, pid: d.pid, memUsed: d.memUsed}})))
})
