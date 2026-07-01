#!/usr/bin/env bash
#
# cleansing-folder.sh
# Housekeeping script untuk membersihkan file .png di suatu folder
# berdasarkan rentang waktu atau umur file (mtime).
#
set -euo pipefail

# ---------- helper: warna output ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

die() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# ---------- 1. Input lokasi folder ----------
read -rp "Masukkan lokasi folder: " TARGET_DIR

# Expand ~ jika dipakai
TARGET_DIR="${TARGET_DIR/#\~/$HOME}"

if [[ ! -d "$TARGET_DIR" ]]; then
    die "Folder '$TARGET_DIR' tidak ditemukan."
fi

echo -e "${GREEN}OK, folder ditemukan:${NC} $TARGET_DIR"
echo

# ---------- 2. Pilihan mode ----------
echo "Pilih mode pembersihan:"
echo "  1) Rentang waktu tertentu (dari - ke)"
echo "  2) Lebih lama dari waktu tertentu (bulan-tahun)"
read -rp "Pilihan [1/2]: " MODE

# ---------- helper: konversi dd-mm-yyyy -> yyyy-mm-dd, dengan validasi ----------
parse_ddmmyyyy() {
    local input="$1"
    if [[ ! "$input" =~ ^([0-3][0-9])-([0-1][0-9])-([0-9]{4})$ ]]; then
        die "Format tanggal '$input' salah. Gunakan format dd-mm-yyyy."
    fi
    local dd="${BASH_REMATCH[1]}"
    local mm="${BASH_REMATCH[2]}"
    local yyyy="${BASH_REMATCH[3]}"

    # validasi tanggal benar-benar valid
    if ! date -j -f "%d-%m-%Y" "$input" "+%Y-%m-%d" >/dev/null 2>&1; then
        die "Tanggal '$input' tidak valid."
    fi
    date -j -f "%d-%m-%Y" "$input" "+%Y-%m-%d"
}

# ---------- helper: hitung akhir bulan dari mm-yyyy ----------
end_of_month() {
    local input="$1"
    if [[ ! "$input" =~ ^([0-1][0-9])-([0-9]{4})$ ]]; then
        die "Format bulan '$input' salah. Gunakan format mm-yyyy."
    fi
    local mm="${BASH_REMATCH[1]}"
    local yyyy="${BASH_REMATCH[2]}"

    if ! date -j -f "%m-%Y" "$input" "+%Y-%m" >/dev/null 2>&1; then
        die "Bulan/tahun '$input' tidak valid."
    fi

    local next_mm next_yyyy
    if [[ "$mm" == "12" ]]; then
        next_mm="01"
        next_yyyy=$((10#$yyyy + 1))
    else
        next_mm=$(printf "%02d" $((10#$mm + 1)))
        next_yyyy="$yyyy"
    fi

    # hari pertama bulan berikutnya, mundur 1 hari -> hari terakhir bulan ini
    date -j -f "%Y-%m-%d" -v-1d "${next_yyyy}-${next_mm}-01" "+%Y-%m-%d"
}

FROM_EPOCH=""
TO_EPOCH=""

case "$MODE" in
    1)
        read -rp "Dari tanggal (dd-mm-yyyy): " FROM_INPUT
        read -rp "Ke tanggal (dd-mm-yyyy): " TO_INPUT

        FROM_ISO="$(parse_ddmmyyyy "$FROM_INPUT")"
        TO_ISO="$(parse_ddmmyyyy "$TO_INPUT")"

        FROM_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "${FROM_ISO} 00:00:00" "+%s")
        TO_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "${TO_ISO} 23:59:59" "+%s")

        if [[ "$FROM_EPOCH" -gt "$TO_EPOCH" ]]; then
            die "Tanggal 'dari' tidak boleh lebih besar dari tanggal 'ke'."
        fi

        echo -e "${CYAN}Mode: rentang waktu ${FROM_INPUT} s/d ${TO_INPUT}${NC}"
        ;;
    2)
        read -rp "Masukkan bulan dan tahun (mm-yyyy), contoh 01-2024: " MY_INPUT
        CUTOFF_ISO="$(end_of_month "$MY_INPUT")"
        TO_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "${CUTOFF_ISO} 23:59:59" "+%s")
        FROM_EPOCH=0

        echo -e "${CYAN}Mode: file dari ${MY_INPUT} dan lebih lama (sampai dengan ${CUTOFF_ISO})${NC}"
        ;;
    *)
        die "Pilihan '$MODE' tidak valid."
        ;;
esac

echo

# ---------- 3. Kumpulkan daftar file yang cocok ----------
echo "Memindai file .png di folder..."

MATCHED_FILES=()
TOTAL_SIZE=0

while IFS= read -r -d '' file; do
    mtime=$(stat -f "%m" "$file")
    if [[ "$mtime" -ge "$FROM_EPOCH" && "$mtime" -le "$TO_EPOCH" ]]; then
        MATCHED_FILES+=("$file")
        size=$(stat -f "%z" "$file")
        TOTAL_SIZE=$((TOTAL_SIZE + size))
    fi
done < <(find "$TARGET_DIR" -maxdepth 1 -type f -iname "*.png" -print0)

TOTAL_COUNT=${#MATCHED_FILES[@]}

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}Tidak ada file yang cocok dengan kriteria. Tidak ada yang perlu dihapus.${NC}"
    exit 0
fi

# format ukuran ke human readable
human_size() {
    local bytes="$1"
    if [[ "$bytes" -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ "$bytes" -lt 1048576 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB", b/1024 }'
    elif [[ "$bytes" -lt 1073741824 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB", b/1048576 }'
    else
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB", b/1073741824 }'
    fi
}

echo
echo -e "${YELLOW}Ditemukan ${TOTAL_COUNT} file yang akan dihapus.${NC}"
echo -e "${YELLOW}Total perkiraan ukuran: $(human_size "$TOTAL_SIZE")${NC}"
echo

# ---------- 4. Konfirmasi ----------
read -rp "Lanjutkan penghapusan? (yes/no): " CONFIRM
CONFIRM_LOWER=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')

if [[ "$CONFIRM_LOWER" != "yes" && "$CONFIRM_LOWER" != "y" ]]; then
    echo -e "${CYAN}Dibatalkan. Tidak ada file yang dihapus.${NC}"
    exit 0
fi

# ---------- 5. Proses hapus dengan progress ----------
echo
CURRENT=0
FAILED=0

for file in "${MATCHED_FILES[@]}"; do
    CURRENT=$((CURRENT + 1))
    if rm -f "$file" 2>/dev/null; then
        printf "\rMenghapus file: %d/%d" "$CURRENT" "$TOTAL_COUNT"
    else
        FAILED=$((FAILED + 1))
        echo -e "\n${RED}Gagal menghapus: $file${NC}"
    fi
done

echo
echo

if [[ "$FAILED" -eq 0 ]]; then
    echo -e "${GREEN}Selesai. ${TOTAL_COUNT} file berhasil dihapus.${NC}"
else
    echo -e "${YELLOW}Selesai dengan ${FAILED} kegagalan dari ${TOTAL_COUNT} file.${NC}"
fi
