#!/usr/bin/fish
set NAME (basename (pwd))
set STDIN /srv/minecraft/input/$NAME

set OTHER_JAVA_OPTS '-XX:+UnlockExperimentalVMOptions -XX:+FlightRecorder -Dlog4j2.formatMsgNoLookups=true -Dlog4j.configurationFile=/srv/minecraft/jars/log4j2_112-116.xml'
set GC_OPTS '-XX:+UseG1GC -XX:+DisableExplicitGC -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=80 -XX:G1MixedGCLiveThresholdPercent=85 -XX:+AlwaysPreTouch -XX:+UseTransparentHugePages -XX:+UseLargePages -XX:LargePageSizeInBytes=2M -XX:+ParallelRefProcEnabled'
#GCOPTS='-XX:+UseConcMarkSweepGC -XX:MaxGCPauseMillis=100'
set HEAP_OPTS '-Xmx4094M -Xms4094M -XX:HeapBaseMinAddress=1 -XX:+HeapDumpOnOutOfMemoryError'
set -x JAVA_HOME /usr/lib/jvm/java-17-openjdk-amd64/

set MAVEN https://maven.fabricmc.net/
set FABRIC_LOADER_VERSION 0.14.18
set TINY_MAPPINGS_PARSER_VERSION 0.3.0+build.17
set MIXIN_VERSION 0.12.4+mixin.0.8.5
set TINY_REMAPPER_VERSION 0.8.2
set ACCESS_WIDENER_VERSION 2.1.0
set ASM_VERSION 9.4

function make-input
  if test ! -p "$STDIN"
    mkfifo $STDIN
  end
end

function artifact
  echo /srv/minecraft/jars/(artifact-rel $argv)
end

function artifact-rel
  if test (count $argv) -gt 3
    echo (echo $argv[1] | tr . /)/$argv[2]/$argv[3]/$argv[2]-$argv[3]-$argv[4].jar
  else
    echo (echo $argv[1] | tr . /)/$argv[2]/$argv[3]/$argv[2]-$argv[3].jar
  end
end

function artifact-dl
  set file (artifact $argv[2..-1])
  if test ! -e "$file"
    mkdir -p (dirname "$file")
    curl -o "$file" "$argv[1]/"(artifact-rel $argv[2..-1]) > /dev/null
  end
  echo $file
end

function vanilla-jar
  set JAR (artifact com.mojang minecraft $argv[1] server)
  if test ! -e "$JAR"
    set manifest_url (curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r '.versions[] | select(.id == "'$argv[1]'") | .url')
    set server_jar_url (curl -s $manifest_url | jq -r '.downloads.server.url')
    mkdir -p (dirname "$JAR")
    curl -o "$JAR" "$server_jar_url"
  end
  echo $JAR
end 

function launch-vanilla
  if test (count $argv) -gt 1
    launch-jar (vanilla-jar $argv[1]) $argv[2..-1]
  else
    launch-jar (vanilla-jar $argv[1])
  end
end

function setup-fabric
  set intermediary_jar (artifact net.fabricmc intermediary $argv[1])
  if test ! -e "$intermediary_jar"
    mkdir -p (dirname "$intermediary_jar")
    curl -o "$intermediary_jar" "https://maven.fabricmc.net/net/fabricmc/intermediary/$argv[1]/intermediary-$argv[1].jar"
  end
end

function launch-fabric
  setup-fabric "$argv[1]"
  if test -e mods
    rm -rf mods
  end
  if test -e "mods-$argv[1]"
    cp -r "mods-$argv[1]" mods
  end
  echo serverJar=(vanilla-jar "$argv[1]") > fabric-server-launcher.properties
  set tiny_mp (artifact-dl $MAVEN net.fabricmc tiny-mappings-parser "$TINY_MAPPINGS_PARSER_VERSION")
  set mixin (artifact-dl $MAVEN net.fabricmc sponge-mixin "$MIXIN_VERSION")
  set tiny_remapper (artifact-dl $MAVEN net.fabricmc tiny-remapper "$TINY_REMAPPER_VERSION")
  set access_widener (artifact-dl $MAVEN net.fabricmc access-widener "$ACCESS_WIDENER_VERSION")
  set asm (artifact-dl $MAVEN org.ow2.asm asm "$ASM_VERSION")
  set asm_analysis (artifact-dl $MAVEN org.ow2.asm asm-analysis "$ASM_VERSION")
  set asm_commons (artifact-dl $MAVEN org.ow2.asm asm-commons "$ASM_VERSION")
  set asm_tree (artifact-dl $MAVEN org.ow2.asm asm-tree "$ASM_VERSION")
  set asm_util (artifact-dl $MAVEN org.ow2.asm asm-util "$ASM_VERSION")
  set fabric_loader (artifact-dl $MAVEN net.fabricmc fabric-loader "$FABRIC_LOADER_VERSION")
  set intermediary (artifact-dl $MAVEN net.fabricmc intermediary "$argv[1]")
  set cp "$tiny_mp":"$mixin":"$tiny_remapper":"$access_widener":"$asm":"$asm_analysis":"$asm_commons":"$asm_tree":"$asm_util":"$fabric_loader":"$intermediary"
  set mainClass net.fabricmc.loader.launch.server.FabricServerLauncher
  if test (count $argv) -gt 1
    launch-cp $cp $mainClass $argv[2..-1]
  else
    launch-cp $cp $mainClass
  end
end

function launch-jar
  make-input
  exec bash -c "exec tail -f $STDIN | exec -a $NAME $JAVA_HOME/bin/java $OTHER_JAVA_OPTS $HEAP_OPTS $GC_OPTS -jar $argv nogui"
end

function launch-cp
  make-input
  exec bash -c "exec tail -f $STDIN | exec -a $NAME $JAVA_HOME/bin/java $OTHER_JAVA_OPTS $HEAP_OPTS $GC_OPTS -cp $argv nogui"
end
