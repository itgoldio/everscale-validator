#!/usr/bin/env bash

# ilya.vasilev@itglobal.com, 2021, 2022, 2023
# https://itgold.io
# https://github.com/itgoldio


### vars
# states for exit codes
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown

getScriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
cd $getScriptDir

[[ -f ton-env.sh ]] && source ton-env.sh
[[ -f ever-env.sh ]] && source ever-env.sh

Depool_addr=$DEPOOL_ADDR
Validator_addr=$VALIDATOR_WALLET_ADDR

timeDelayBeforeElectionsEnd=60
timeDelayAfterElectionStart=1800

# utils
bcBin=$( which bc )
bcArgs=" -ql "
bcLib="${getScriptDir}/bcLibForFloating"

grepBin=$( which grep | grep -v alias )
cutBin=$( which cut )
trBin=$( which tr )
tailBin=$( which tail )
tailLines=100
headBin=$( which head )
divideValue=1000000000
awkBin=$( which awk )

version="0.8.0"

# show usage/help info and exit
usage() {
  echo "Usage: $0, ver. ${version}
-h   -- this help
-w   -- warning
-c   -- critical
-C   -- tonos-cli config file
-e   -- env-file
-t   -- type
      
    These checks calls without -w and -c params:
          isValidatingNow
          isValidatingNext
          partCheck
          getConsoleVersion
          getTonosCliVersion
          getRNodeVersion

    These checks requires warning and critical param:
          dePoolBalance
          timeDiff


  " 1>&2
  exit $STATE_UNKNOWN
}

isItElectionTime() {
  electionID=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getconfig 34"  | jq -r ".p34.utime_until" )
  elections_start_before=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getconfig 15" | jq -r ".p15.elections_start_before" )
  elections_end_before=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getconfig 15" | jq -r ".p15.elections_end_before" )
  (( electionStart = electionID - elections_start_before ))
  (( electionEnd = electionID - elections_end_before ))
  (( timeToCheckBeforeEndElections = electionEnd - timeDelayBeforeElectionsEnd ))
  (( timeToCheckAfterStartElections = electionStart + timeDelayAfterElectionStart ))
  curEpoch=$( date +%s )
  
  [[ $curEpoch -le $timeToCheckBeforeEndElections && $curEpoch -ge $timeToCheckAfterStartElections ]] && echo "true" || echo "false"
}

getConsoleVersion() {
  ${TON_CONSOLE} --version | ${headBin} -n20 | ${awkBin} '{print $2}'
}

getTonosCliVersion() {
  ${TON_CLI} --version | ${headBin} -n 20 | ${grepBin} tonos_cli | awk '{print $2}'
}

getRNodeVersion() {
  ${RNODE_BIN} --version | ${headBin} -n20 | ${grepBin} version | awk '{print $4}'
}

getDePoolBalance() {
  versionAsNumber=$( echo "$( getTonosCliVersion )" | sed 's/\.//g' )
  oldVersion="0246"
  freshVersion="0352"
  if [[ $((10#$versionAsNumber)) -le $((10#$oldVersion)) || $((10#$versionAsNumber)) -ge $((10#$freshVersion)) ]]
  then
    myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG account $DEPOOL_ADDR | jq -r ".balance" )
  else
    myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG account $DEPOOL_ADDR | jq -r ".[].balance" )
  fi
  [[ -n $myRes ]] && echo $myRes || echo ""
}

checkStatus() {

  # *Balance - using script ./ton-*-balance.sh
  #   returning values from script: long
  #   returning code by check should be prepared:
  #     value / 1000000000 ? 30 >     -> 0 - ok
  #     value / 1000000000 ? 20..29   -> 1 - warn
  #     value / 1000000000 ? 19 <     -> 2 - crit
  #                                   -> 3 - unknown
  #    23.06.2021 - Dont using rounding now =)
  #     43772151034
  #    25.06.2021 - lets round!!!

  type=${1}
  warnValue=${2}
  critValue=${3}
  curValue=${4}
    
  case "$type" in
    walletBalance ) myMsg="Node wallet balance:" ;;
    dePoolBalance ) curValue=$( getDePoolBalance ) ; myMsg="DePool balance:" ;;
    proxy1balance ) myMsg="DePool proxy 1 balance:" ;;
    proxy2balance ) myMsg="DePool proxy 2 balance:" ;;
    tickTokBalance ) myMsg="TickTok balance:" ;;
  esac

  if [[ -z $curValue ]]
  then
    echo "UNKNOWN - $myMsg -1 | $type=-1;$warnValue;$critValue;;"
    exit $STATE_UNKNOWN
  fi

  evalRes=$( echo "$curValue/$divideValue" | ${bcBin} ${bcArgs} ${bcLib} )
  isWarn=$( echo "$evalRes<=$warnValue" | ${bcBin} ${bcArgs} ${bcLib} )
  isCrit=$( echo "$evalRes<=$critValue" | ${bcBin} ${bcArgs} ${bcLib} )

  if [[ $isWarn -ne 1 && $isCrit -ne 1 ]]
  then
    echo "OK - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_OK
  elif [[ $isWarn -eq 1 && $isCrit -ne 1 ]]
  then
    echo "WARNING - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_WARNING
  elif [[ $isCrit -eq 1 ]]
  then
    echo "CRITICAL - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_CRITICAL
  else
    echo "UNKNOWN - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_UNKNOWN
  fi
}

getElectorAddr() {
  $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c 'getconfig 1' | grep -iq error
  if [[ $? -ne 0 ]]
  then
    myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getconfig 1" | jq -r '.p1' )
    [[ -n $myRes ]] && echo "-1:${myRes}" || echo ""
  fi
}

getCurrentElectionsID() {
  # Ровно до тех пор пока мы едем в мейне на фифте
  # fift
  myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG runget $( getElectorAddr ) active_election_id | jq -r ".value0" )
  [[ -n $myRes ]] && echo "${myRes}" || echo ""
  # solidity
  # myRes=$( $TON_CLI -j run $( getElectorAddr ) active_election_id '{}' --abi ${Elector_ABI} | jq -r '.value0')
  # [[ -n $myRes ]] && echo "${myRes}" || echo ""
}

getAccountBalance() {
  myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getaccount $VALIDATOR_WALLET_ADDR" | jq -r ".balance" )
  [[ -n $myRes ]] && echo $myRes || echo ""
}

isValidatingNow() {
  myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getstats" | jq -r ".in_current_vset_p34" )
  if [[ -n $myRes ]]
  then
    if [[ "$myRes" == "true" ]]
    then
      echo "Current validator exist in P34 ( check via console: $myRes )"
      exit $STATE_OK
    elif [[ "$myRes" == "false" ]]
    then
      echo "Current validator not in P34 ( check via console: $myRes )"
      exit $STATE_CRITICAL
    fi
  else
    echo "Console return error output. Can not parse"
    exit $STATE_UNKNOWN
  fi
}

isValidatingNext() {
  isElectionsAreOpen=$( isItElectionTime )
  if [[ ${isElectionsAreOpen} == "false" ]]
  then
    echo -e "UNKNOWN - There is no information about this | validatingNext=-1;;;;"
    exit $STATE_OK
  elif [[ ${isElectionsAreOpen} == "true" ]]
  then
    myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getstats" | jq -r ".in_next_vset_p36" )
    if [[ "$myRes" == "true" ]]
    then
      echo "OK - Node will validate next round: 1 | validatingNext=1;;;;"
      exit $STATE_OK
    else
      echo "CRITICAL - Node will validate next round: 0 | validatingNext=0;;;;"
      exit $STATE_CRITICAL
    fi
  fi
}

getTimeDiff() {
# timeDiff  - using script ./ton-node-diff.sh
#   returning values from script: integer
#   checking values and returning code by check
#     1 sec - 600 sec  - normal -> return 0
#     600 sec - 1199 sec - warning -> return 1
#     1200 sec > - critical -> return 2
#     0 < - unknown -> unknown 3
  warnValue=${1}
  critValue=${2}
  myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getstats" | jq -r ".timediff" )
  if [[ "$myRes" -lt "$warnValue" ]]
  then
    echo "OK - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_OK
  elif [[ "$myRes" -ge "$warnValue" && "$myRes" -lt "$critValue" ]]
  then
    echo "WARNING - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_WARNING
  elif [[ "$myRes" -ge "$critValue" ]]
  then
    echo "CRITICAL - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_CRITICAL
  else
    echo "UNKNOWN - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_UNKNOWN
  fi
}

calcWeight() {
  weight=${1}
  [[ "${weight}" == "null" || -z "${weight}" ]] && weight=0
  if [[ -e ${bcBin} ]]
  then
    echo "$( $bcBin -lq <<< "scale=3; ${weight} / 10000000000000000" )"
  else
    echo "${1}"
  fi
}

calcStake() {
  stake=${1}
  [[ "${stake}" == "null" || -z "${stake}" ]] && stake=0
  if [[ -e ${bcBin} ]]
  then
    echo "$( $bcBin -lq <<< "scale=3; ${stake} / 1000000000" )"
  else
    echo "${1}"
  fi
}

getCurrentADNL() {
  allKeysFromConfig=$( cat $ever_node_config | jq .validator_keys )
  [[ "${allKeysFromConfig}" == "null" ]] && echo "null" && return
  elections0=$( echo $allKeysFromConfig | jq -r .[0].election_id )
  adnlKey0=$( echo $allKeysFromConfig | jq -r .[0].validator_adnl_key_id )
  [[ "${adnlKey0}" == "null" ]] && echo "null" && return
  elections1=$( echo $allKeysFromConfig | jq -r .[1].election_id )
  adnlKey1=$( echo $allKeysFromConfig | jq -r .[1].validator_adnl_key_id )
  if [[ "${adnlKey1}" == "null" ]]
  then
    myADNLKey=$( echo "${adnlKey0}" | base64 -d | od -t xC -An | tr -d '\n' | tr -d ' ' )
    myElectionsID=$elections0
    currADNLKey=${myADNLKey}
    currElectionsID=${myElectionsID}
  else
    currElectionsID=$(( elections0 < elections1 ? elections0 : elections1 ))
    nextElectionsID=$(( elections0 > elections1 ? elections0 : elections1 ))
    currADNLKey=$( echo $allKeysFromConfig | jq -r ".[]|select(.election_id == $currElectionsID)|.validator_adnl_key_id" | base64 -d | od -t xC -An | tr -d '\n' | tr -d ' ' )
    nextADNLKey=$( echo $allKeysFromConfig | jq -r ".[]|select(.election_id == $nextElectionsID)|.validator_adnl_key_id" | base64 -d | od -t xC -An | tr -d '\n' | tr -d ' ' )
  fi
  [[ -z "${adnlKey1}" || "${adnlKey1}" == "null" ]] && echo "${currADNLKey} ${currElectionsID}" || echo "${currADNLKey} ${currElectionsID} ${nextADNLKey} ${nextElectionsID}"
}

getP36Config() {
  myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG getconfig 36 | jq -r "." )
  echo "${myRes}"
}

getP34Config() {
  myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG getconfig 34 | jq -r "." )
  echo "${myRes}"
}

findInP34Config() {
  isInP34=$( echo "$( getP34Config )" | jq ".list[]|select(.adnl_addr == \"${1}\")" )
  if [[ -n $isInP34 ]]
  then
    adnl="$( echo ${isInP34} | jq -r .adnl_addr)"
    pkey="$( echo ${isInP34} | jq -r .public_key)"
    wght="$( echo ${isInP34} | jq -r .weight)"
    echo "${adnl} ${pkey} ${wght}"
  else
    echo "null"
  fi
} 

findInP36Config() {
  myRes=$( getP36Config )
  [[ $myRes == "null" ]] && echo "null" && return
  isInp36=$( echo "$( getP36Config )" | jq ".list[]|select(.adnl_addr == \"${1}\")" )
  if [[ -n $isInp36 ]]
  then
    adnl="$(echo ${isInp36} | jq -r .adnl_addr )"
    pkey="$(echo ${isInp36} | jq -r .public_key )"
    wght="$(echo ${isInp36} | jq -r .weight_dec )"
    echo "${adnl} ${pkey} ${wght}"
  else
    echo "null"
  fi
}

getParticipantListInElector() {
  myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG runget $( getElectorAddr ) participant_list_extended )  
  echo "${myRes}"
}

getElectionsFromElector() {
  myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG runget $( getElectorAddr ) participant_list_extended | jq -r ".value0" )
  echo "${myRes}"
}

isValidatorInElector() {
  [[ -z ${1} || ! -n ${1} ]] && echo "null" && return
  myADNL=${1}
  isElectionsOnGoing=$( getElectionsFromElector )
  [[ $isElectionsOnGoing -eq 0 ]] && echo "null" && return
  myRes=$( getParticipantListInElector )
  # validatorInfo=$( echo "${myRes}" | sed 's/] ],/]],\n/g' | grep ${myADNL} )
  # validatorInfo=$( echo "${validatorInfo}" | sed -E 's/\[|\"|\]|\,//g' )
  # validatorInfo=$( echo "${validatorInfo}" | sed 's/\[//g;s/,//g;s/"//g' )
  validatorInfo=$( echo $myRes | sed 's/] ],/]],\n/g' | grep ${myADNL} | sed 's/\[//g;s/,//g;s/"//g' )

  if [[ -n ${validatorInfo} ]]
  then
    validatorPublicKey=$( echo "${validatorInfo}" | awk '{print $1}' )
    validatorStake=$( calcStake $( echo "${validatorInfo}" | awk '{print $2}' ) )
    validatorMaxFactor=$( echo "${validatorInfo}" | awk '{print $3}' )
    validatorProxyAddr=$( echo "${validatorInfo}" | awk '{print $4}' )
    validatorADNLAddr=$( echo "${validatorInfo}" | awk '{print $5}' )
  else
    echo "absent"
    return
  fi
  echo "PubKey: ${validatorPublicKey} Stake: ${validatorStake} MaxFactor: ${validatorMaxFactor} ProxyAddr: ${validatorProxyAddr} ADNL: ${validatorADNLAddr}"
}

partCheck() {
  getADNLInfo=$( getCurrentADNL )
  [[ "${getADNLInfo}" == "null" ]] && echo "Validator never elected yet. ADNL is empty" && exit $STATE_UNKNOWN
  electionsID=$( getCurrentElectionsID )
  if [[ "${electionsID}" -eq 0 ]]
  then
    myMSG="There is no election period\n"
    flagElection=1
  else
    myMSG="ElectionsID $electionsID, validating round start at $( date -d@${electionsID} "+%F %T" )\n"
    flagElection=0
  fi

  currADNL=$( echo ${getADNLInfo} | awk '{print $1}' )
  currADNLReadyFrom=$( echo ${getADNLInfo} | awk '{print $2}' )
  isNextADNLReady=$( echo ${getADNLInfo} | awk '{print $3}' )
  isNextADNLReadyFrom=$( echo ${getADNLInfo} | awk '{print $4}' )

  if [[ -z ${isNextADNLReady} ]]
  then  
    myMSG="${myMSG}Current ADNL ${currADNL} valid from ${currADNLReadyFrom} ( $( date -d@${currADNLReadyFrom} ) )\nNext ADNL EMPTY\n"
    flagCurrADNL=1
  else
    myMSG="${myMSG}Current ADNL ${currADNL} valid from ${currADNLReadyFrom} ( $( date -d@${currADNLReadyFrom} ) )\nNext ADNL ${isNextADNLReady} valid from ${isNextADNLReadyFrom} ( $( date -d@${isNextADNLReadyFrom} ) )\n"
    flagCurrADNL=0
  fi

  errMSG="\n"

  # search nextadnl
  searchedADNL=$( findInP36Config $isNextADNLReady )
  if [[ "${searchedADNL}" != "null" ]]
  then
    myMSG="${myMSG}P36: ADNL: $( echo ${searchedADNL} | awk '{print $1}' ) PubKey: $( echo ${searchedADNL} | awk '{print $2}' ) Weight: $( calcWeight $( echo ${searchedADNL} | awk '{print $3}' ) ) \n"
    flagP36Next=0
  else
    errMSG="${errMSG}P36: isNextADNLReady are EMPTY ( func return ${searchedADNL} )\n"
    flagP36Next=1
  fi

  searchedADNL=$( findInP34Config $isNextADNLReady )
  if [[ "${searchedADNL}" != "null" ]]
  then
    myMSG="${myMSG}P34: ADNL: $( echo ${searchedADNL} | awk '{print $1}' ) PubKey: $( echo ${searchedADNL} | awk '{print $2}' ) Weight: $( calcWeight $( echo ${searchedADNL} | awk '{print $3}' ) ) \n"
    flagP34Next=0
  else
    errMSG="${errMSG}P34: isNextADNLReady are EMPTY ( func return ${searchedADNL} )\n"
    flagP34Next=1
  fi

  # search curradnl
  searchedADNL=$( findInP36Config $currADNL )
  if [[ "${searchedADNL}" != "null" ]]
  then
    myMSG="${myMSG}P36 ADNL: $( echo ${searchedADNL} | awk '{print $1}' ) PubKey: $( echo ${searchedADNL} | awk '{print $2}' ) Weight: $( calcWeight $( echo ${searchedADNL} | awk '{print $3}' ) ) \n"
    flagP36Curr=0
  else
    errMSG="${errMSG}P36: currADNL are EMPTY ( func return ${searchedADNL} )\n"
    flagP36Curr=1
  fi

  searchedADNL=$( findInP34Config $currADNL )
  if [[ "${searchedADNL}" != "null" ]]
  then
    myMSG="${myMSG}P34: ADNL: $( echo ${searchedADNL} | awk '{print $1}' ) PubKey: $( echo ${searchedADNL} | awk '{print $2}' ) Weight: $( calcWeight $( echo ${searchedADNL} | awk '{print $3}' ) ) \n"
    flagP34Curr=0
  else
    errMSG="${errMSG}P34: currADNL are EMPTY ( func return ${searchedADNL} )\n"
    flagP34Curr=1
  fi

  if [[ "${electionsID}" -ne 0 ]]
  then
    isElectionsAreOpen=$( isItElectionTime )
    if [[ ${isElectionsAreOpen} == "true" ]]
    then
      allValidatorsInElector=$( getParticipantListInElector )
      if [[ ! -z $isNextADNLReady && -n $isNextADNLReady ]]
      then
        myCheck=$( echo ${allValidatorsInElector} | $grepBin -q $isNextADNLReady )
        if [[ $? -eq 0 ]]
        then
          findNextADNLInElector=$( isValidatorInElector $isNextADNLReady )
          # if [[ -n "${findNextADNLInElector}" && "${findNextADNLInElector}" != "null" ]]
          # then
            myMSG="${myMSG}Validator info from Elector:\n$findNextADNLInElector\n"
            flagNextInElector=0
          # fi
        else
          errMSG="${errMSG}isNextADNLReady in Elector are empty! (func return: ${findNextADNLInElector} )\n"
          flagNextInElector=1
        fi
      else
        errMSG="${errMSG}Next ADNL NOT SET! First time?\n"
        flagNextInElector=0
      fi  

      if [[ ! -z $currADNL && -n $currADNL ]]
      then
        myCheck=$( echo ${allValidatorsInElector} | $grepBin -q ${currADNL} )
        if [[ $? -eq 0 ]]
        then
          findCurrADNLInElector=$( isValidatorInElector $currADNL )
          # if [[ -n "${findCurrADNLInElector}" && "${findCurrADNLInElector}" != "null" ]]
          # then
            myMSG="${myMSG}Validator info from Elector:\n$findCurrADNLInElector\n"
            flagCurrInElector=0
          # fi
        else
          errMSG="${errMSG}currADNL in Elector are empty! (func return: ${findCurrADNLInElector} )\n"
          flagCurrInElector=1
        fi
      else
        errMSG="${errMSG}Current ADNL NOT SET! Validator not configured?\n"
        flagNextInElector=1
      fi
    fi
  fi

  echo -e "GRAND TOTAL:\n
${myMSG}\n
ErrMsg: ${errMSG}\n
flagElection ${flagElection} | flagElection=${flagElection};;;;\n
flagCurrADNL ${flagCurrADNL} | flagCurrADNL=${flagCurrADNL};;;;\n
flagP36Next ${flagP36Next} | flagP36Next=${flagP36Next};;;;\n
flagP34Next ${flagP34Next} | flagP34Next=${flagP34Next};;;;\n
flagP36Curr ${flagP36Curr} | flagP36Curr=${flagP36Curr};;;;\n
flagP34Curr ${flagP34Curr} | flagP34Curr=${flagP34Curr};;;;\n
flagNextInElector ${flagNextInElector:=-1} | flagNextInElector=${flagNextInElector:=-1};;;;\n
flagCurrInElector ${flagCurrInElector:=-1} | flagCurrInElector=${flagCurrInElector:=-1};;;;\n
"
  if [[ ${isElectionsAreOpen} == "true" ]]
  then
    if [[ $flagNextInElector -eq 1 ]]
    then
      # next and current ADNL not ready - exit crit
      if [[ $flagCurrInElector -eq 1 ]]
      then
        echo -e "Current ADNL ( first time validating ) not present in Elector\nNext ADNL not present in Elector"
        exit $STATE_CRITICAL 
      fi
    # next adnl ready - exit ok
    elif [[ $flagNextInElector -eq 0 ]]
    then
      exit $STATE_OK
    # next adnl not ready but curr adnl ready - exit ok ( first time validate )
    elif [[ $flagCurrInElector -eq 0 ]]
    then
      exit $STATE_OK
    fi
  else
    # elections not open - exit ok
    exit $STATE_OK
  fi
}


### main script

if [ -z "${1}" ]
then
  usage
fi

while getopts ":w:c:t:hC:e:" myArgs
do
  case ${myArgs} in
    w) warnValue=${OPTARG} ;;
    c) critValue=${OPTARG} ;;
    t) typeCheck=${OPTARG} ;;
    C) configFile=${OPTARG} ;;
    e) envFile=${OPTARGS} ;;
    h) usage ;;
    \?)  echo "Wrong option given. Check help ( $0 -h ) for usage."
        exit $STATE_UNKNOWN
        ;;
  esac
done


if [[ -n ${envFile} ]]; then
  if [[ ! -f ${envFile} ]]; then
    echo "Passed env file ${envFile} not exist"
    exit $STATE_UNKNOWN
  fi
  source ${envFile}
fi

if [[ "${typeCheck}" == "isValidatingNow" ]]
then
  isValidatingNow
elif [[ "${typeCheck}" == "isValidatingNext" ]]
then
  isValidatingNext
elif [[ "${typeCheck}" == "partCheck" ]]
then
  partCheck
elif [[ "${typeCheck}" == "getConsoleVersion" ]]
then
  getConsoleVersion
elif [[ "${typeCheck}" == "getTonosCliVersion" ]]
then
  getTonosCliVersion
elif [[ "${typeCheck}" == "getRNodeVersion" ]]
then
  getRNodeVersion
elif [[ -n "${typeCheck}" && -n "${warnValue}" && -n "${critValue}" ]]
then
  while true
  do
    case "$typeCheck" in
      timeDiff ) getTimeDiff "${warnValue}" "${critValue}" ;;
      walletBalance )
        checkStatus walletBalance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${walletBalanceScript}" ) ;;
      dePoolBalance )
        checkStatus dePoolBalance "${warnValue}" "${critValue}" ;;
      proxy1balance )
        checkStatus proxy1balance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${depoolproxy1BalanceScript}" 2>/dev/null ) ;;
      proxy2balance )
        checkStatus proxy2balance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${depoolproxy2BalanceScript}" 2>/dev/null ) ;;
      tickTokBalance )
        checkStatus tickTokBalance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${tickTokBalanceScript}" ) ;;
      * )
        usage
        exit ${STATE_UNKNOWN}
        ;;
    esac
  done
else
  echo -e "Missing required parameter or parameters"
  usage
  exit ${STATE_UNKNOWN}
fi


