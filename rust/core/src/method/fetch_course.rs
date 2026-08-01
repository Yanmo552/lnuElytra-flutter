use serde::{Deserialize, Serialize};
use std::collections::HashSet;

use crate::{
    Client,
    course::{Course, Jxb},
    def,
    error::{Error, R},
    utils::{
        ToHtml, ToJson,
        macros::{info, warn},
    },
};

impl Client {
    pub async fn fetch_courses(&self, q: &str) -> R<Course> {
        info!("query course, q: {}", q);

        #[derive(Serialize, Debug)]
        struct PDRQ<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xbm: &'a str, ccdm: &'a str, kklxdm: &'a str, xkxnm: &'a str, xkxqm: &'a str,
            jg_id: &'a str, xsbj: &'a str, mzm: &'a str, xz: &'a str,
            bh_id: &'a str, xqh_id: &'a str, zyfx_id: &'a str, xslbdm: &'a str,
            kspage: &'a str, jspage: &'a str,
            // extra params from Display/Index page (needed by some schools)
            rwlx: &'a str, xklc: &'a str, xkly: &'a str, bklx_id: &'a str,
            xkkz_id: &'a str, zyh_id: &'a str, njdm_id: &'a str,
            njdm_id_1: &'a str, zyh_id_1: &'a str,
            gnjkxdnj: &'a str, bjgkczxbbjwcx: &'a str, bbhzxjxb: &'a str,
            sfkkjyxdxnxq: &'a str, kzkcgs: &'a str,
            sfkknj: &'a str, sfkkzy: &'a str, kzybkxy: &'a str,
            sfznkx: &'a str, zdkxms: &'a str, sfkxq: &'a str,
            sfkcfx: &'a str, kkbk: &'a str, kkbkdj: &'a str,
            sfkgbcx: &'a str, sfrxtgkcxd: &'a str, tykczgxdcs: &'a str,
            rlkz: &'a str, xkzgbj: &'a str, jxbzb: &'a str,
        }

        let pd = PDRQ {
            filter_list: q.into(),
            xbm: self.use_store("xbm"), ccdm: self.use_store("ccdm"), kklxdm: self.use_store("firstKklxdm"),
            xkxnm: self.use_store("xkxnm"), xkxqm: self.use_store("xkxqm"), jg_id: self.use_store("jg_id_1"),
            xsbj: self.use_store("xsbj"), mzm: self.use_store("mzm"), xz: self.use_store("xz"),
            bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"), zyfx_id: self.use_store("zyfx_id"),
            xslbdm: self.use_store("xslbdm"), kspage: "1", jspage: "10",
            rwlx: self.use_store("rwlx"), xklc: self.use_store("xklc"), xkly: self.use_store("xkly"),
            bklx_id: self.use_store("bklx_id"), xkkz_id: self.use_store("firstXkkzId"),
            zyh_id: self.use_store("zyh_id"), njdm_id: self.use_store("njdm_id"),
            njdm_id_1: self.use_store("njdm_id_1"), zyh_id_1: self.use_store("zyh_id_1"),
            gnjkxdnj: self.use_store("gnjkxdnj"), bjgkczxbbjwcx: self.use_store("bjgkczxbbjwcx"),
            bbhzxjxb: self.use_store("bbhzxjxb"), sfkkjyxdxnxq: self.use_store("sfkkjyxdxnxq"),
            kzkcgs: self.use_store("kzkcgs"),
            sfkknj: self.use_store("sfkknj"), sfkkzy: self.use_store("sfkkzy"),
            kzybkxy: self.use_store("kzybkxy"), sfznkx: self.use_store("sfznkx"),
            zdkxms: self.use_store("zdkxms"), sfkxq: self.use_store("sfkxq"),
            sfkcfx: self.use_store("sfkcfx"), kkbk: self.use_store("kkbk"),
            kkbkdj: self.use_store("kkbkdj"), sfkgbcx: self.use_store("sfkgbcx"),
            sfrxtgkcxd: self.use_store("sfrxtgkcxd"), tykczgxdcs: self.use_store("tykczgxdcs"),
            rlkz: self.use_store("rlkz"), xkzgbj: self.use_store("xkzgbj"),
            jxbzb: self.use_store("jxbzb"),
        };

        #[derive(Deserialize, Debug)]
        struct PDRS { #[serde(rename = "tmpList")] tmp_list: Vec<PDIS>, }
        impl PDRS { fn first_kch(&self) -> R<&String> { Ok(&self.tmp_list.get(0).ok_or(Error::JxbNotFound("pd.0"))?.kch_id) } }
        #[derive(Deserialize, Debug)]
        struct PDIS { kch_id: String, #[serde(default)] kcmc: String, }

        let pdr = self.post(def::SELECT_COURSE_PART_DISPLAY_URL)?.form(&pd).send().await?.jsonr::<PDRS>().await?;
        let kcmc = pdr.tmp_list.get(0).map(|x| x.kcmc.clone()).unwrap_or_default();

        #[derive(Serialize, Debug)]
        struct QDRQ<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xkxqm: &'a str, xkxnm: &'a str, xkkz_id: &'a str, bklx_id: &'a str, kch_id: &'a str,
            njdm_id: &'a str, xsbj: &'a str, xz: &'a str, mzm: &'a str, kklxdm: &'a str,
            bh_id: &'a str, xqh_id: &'a str, xslbdm: &'a str, zyfx_id: &'a str,
            jg_id: &'a str, ccdm: &'a str, xbm: &'a str,
            // extra params from Display page
            rwlx: &'a str, xkly: &'a str, xklc: &'a str,
            zyh_id: &'a str, txbsfrl: &'a str,
            sfkkjyxdxnxq: &'a str, kzkcgs: &'a str,
            gnjkxdnj: &'a str, sfkknj: &'a str, sfkkzy: &'a str,
            kzybkxy: &'a str, sfznkx: &'a str, zdkxms: &'a str,
            sfkxq: &'a str, sfkcfx: &'a str,
            bbhzxjxb: &'a str, kkbk: &'a str, kkbkdj: &'a str,
            xkxskcgskg: &'a str, rlkz: &'a str, cdrlkz: &'a str,
            rlzlkz: &'a str, jxbzcxskg: &'a str,
            cxbj: &'a str, fxbj: &'a str,
        }

        let qd = QDRQ {
            filter_list: q.into(),
            xkxqm: self.use_store("xkxqm"), xkxnm: self.use_store("xkxnm"), xkkz_id: self.use_store("firstXkkzId"),
            bklx_id: self.use_store("bklx_id"), kch_id: &pdr.first_kch()?, njdm_id: self.use_store("njdm_id"),
            xsbj: self.use_store("xsbj"), xz: self.use_store("xz"), mzm: self.use_store("mzm"),
            kklxdm: self.use_store("firstKklxdm"), bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"),
            xslbdm: self.use_store("xslbdm"), zyfx_id: self.use_store("zyfx_id"),
            jg_id: self.use_store("jg_id_1"), ccdm: self.use_store("ccdm"), xbm: self.use_store("xbm"),
            rwlx: self.use_store("rwlx"), xkly: self.use_store("xkly"), xklc: self.use_store("xklc"),
            zyh_id: self.use_store("zyh_id"), txbsfrl: self.use_store("txbsfrl"),
            sfkkjyxdxnxq: self.use_store("sfkkjyxdxnxq"), kzkcgs: self.use_store("kzkcgs"),
            gnjkxdnj: self.use_store("gnjkxdnj"), sfkknj: self.use_store("sfkknj"),
            sfkkzy: self.use_store("sfkkzy"), kzybkxy: self.use_store("kzybkxy"),
            sfznkx: self.use_store("sfznkx"), zdkxms: self.use_store("zdkxms"),
            sfkxq: self.use_store("sfkxq"), sfkcfx: self.use_store("sfkcfx"),
            bbhzxjxb: self.use_store("bbhzxjxb"), kkbk: self.use_store("kkbk"),
            kkbkdj: self.use_store("kkbkdj"), xkxskcgskg: self.use_store("xkxskcgskg"),
            rlkz: self.use_store("rlkz"), cdrlkz: self.use_store("cdrlkz"),
            rlzlkz: self.use_store("rlzlkz"), jxbzcxskg: self.use_store("jxbzcxskg"),
            cxbj: self.use_store("cxbj"), fxbj: self.use_store("fxbj"),
        };

        #[derive(Deserialize, Debug)]
        struct QDRS { do_jxb_id: String, jsxx: String, jxb_id: String, sksj: String, }

        let qdr = self.post(def::SELECT_COURSE_QUERY_DO_WITH_COURSE_ID_URL)?.form(&qd).send().await?.jsonr::<Vec<QDRS>>().await?;

        let mut course = Course {
            xkkz_id: self.stores.get("firstXkkzId").ok_or(Error::Missing("[firstXkkzId]".into()))?.into(),
            kch_id: pdr.first_kch()?.into(), kcmc, jxb: vec![],
        };
        for item in qdr {
            course.jxb.push(Jxb { jxb_id: item.jxb_id, do_id: item.do_jxb_id, jsxx: item.jsxx, sksj: item.sksj, jxbmc: String::new() });
        }
        if course.jxb.is_empty() { warn!("{} query jxb empty", q); }
        info!("fetch course success"); Ok(course)
    }

    /// Fetch all courses by brute-forcing kklxdm values (01-30) + discovered tabs
    pub async fn fetch_courses_all(&self, q: &str) -> R<Vec<Course>> {
        info!("fetch all courses via brute-force kklxdm, q: {}", q);

        #[derive(Serialize, Debug)]
        struct PDRQ<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xbm: &'a str, ccdm: &'a str, kklxdm: &'a str, xkxnm: &'a str, xkxqm: &'a str,
            jg_id: &'a str, xsbj: &'a str, mzm: &'a str, xz: &'a str,
            bh_id: &'a str, xqh_id: &'a str, zyfx_id: &'a str, xslbdm: &'a str,
            kspage: &'a str, jspage: &'a str,
        }

        #[derive(Deserialize, Debug)]
        struct PDRS { #[serde(rename = "tmpList")] tmp_list: Vec<PDIS>, }
        #[derive(Deserialize, Debug)]
        struct PDIS { kch_id: String, #[serde(default)] kcmc: String, }

        #[derive(Serialize, Debug)]
        struct QDRQ<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xkxqm: &'a str, xkxnm: &'a str, xkkz_id: &'a str, bklx_id: &'a str, kch_id: &'a str,
            njdm_id: &'a str, xsbj: &'a str, xz: &'a str, mzm: &'a str, kklxdm: &'a str,
            bh_id: &'a str, xqh_id: &'a str, xslbdm: &'a str, zyfx_id: &'a str,
            jg_id: &'a str, ccdm: &'a str, xbm: &'a str,
        }

        #[derive(Deserialize, Debug)]
        struct QDRS {
            do_jxb_id: String, jsxx: String, jxb_id: String, sksj: String,
            #[serde(default)] jxbmc: String,
        }

        let default_xkkz_id = self.stores.get("firstXkkzId")
            .ok_or(Error::Missing("[firstXkkzId]".into()))?.clone();
        let mut all_courses: Vec<Course> = Vec::new();
        let mut seen_kch: HashSet<String> = HashSet::new();

        // Collect kklxdm values to try: discovered + brute-force 01-30
        let mut kklxdm_list: Vec<String> = self.get_all_kklxdm();
        for i in 1u32..=30 {
            let s = format!("{i:02}");
            if !kklxdm_list.contains(&s) {
                kklxdm_list.push(s);
            }
        }
        // Also try empty (default)
        if !kklxdm_list.contains(&String::new()) {
            kklxdm_list.push(String::new());
        }

        info!("trying {} kklxdm values", kklxdm_list.len());

        for kklxdm_val in &kklxdm_list {
            // Step 1: part_display
            let pd = PDRQ {
                filter_list: q.into(),
                xbm: self.use_store("xbm"), ccdm: self.use_store("ccdm"), kklxdm: kklxdm_val,
                xkxnm: self.use_store("xkxnm"), xkxqm: self.use_store("xkxqm"), jg_id: self.use_store("jg_id_1"),
                xsbj: self.use_store("xsbj"), mzm: self.use_store("mzm"), xz: self.use_store("xz"),
                bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"), zyfx_id: self.use_store("zyfx_id"),
                xslbdm: self.use_store("xslbdm"), kspage: "1", jspage: "999",
            };

            let resp = match self.post(def::SELECT_COURSE_PART_DISPLAY_URL)?.form(&pd).send().await {
                Ok(r) => r,
                Err(_) => continue,
            };
            let pdr: PDRS = match resp.json().await {
                Ok(p) => p,
                Err(_) => continue,
            };

            if pdr.tmp_list.is_empty() { continue; }

            // Step 2: for each unique kch_id, query_do
            for item in &pdr.tmp_list {
                if !seen_kch.insert(item.kch_id.clone()) { continue; }
                if item.kch_id.is_empty() { continue; }

                let this_xkkz_id = self.get_xkkz_id_for(kklxdm_val).unwrap_or(&default_xkkz_id);
                let qd = QDRQ {
                    filter_list: q.into(),
                    xkxqm: self.use_store("xkxqm"), xkxnm: self.use_store("xkxnm"), xkkz_id: this_xkkz_id,
                    bklx_id: self.use_store("bklx_id"), kch_id: &item.kch_id, njdm_id: self.use_store("njdm_id"),
                    xsbj: self.use_store("xsbj"), xz: self.use_store("xz"), mzm: self.use_store("mzm"),
                    kklxdm: kklxdm_val, bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"),
                    xslbdm: self.use_store("xslbdm"), zyfx_id: self.use_store("zyfx_id"),
                    jg_id: self.use_store("jg_id_1"), ccdm: self.use_store("ccdm"), xbm: self.use_store("xbm"),
                };

                let resp = match self.post(def::SELECT_COURSE_QUERY_DO_WITH_COURSE_ID_URL)?.form(&qd).send().await {
                    Ok(r) => r,
                    Err(_) => continue,
                };
                let items: Vec<QDRS> = match resp.json().await {
                    Ok(i) => i,
                    Err(_) => continue,
                };

                let jxbs: Vec<Jxb> = items.iter().map(|item| Jxb {
                    jxb_id: item.jxb_id.clone(),
                    do_id: item.do_jxb_id.clone(),
                    jsxx: item.jsxx.clone(),
                    sksj: item.sksj.clone(),
                    jxbmc: item.jxbmc.clone(),
                }).collect();

                all_courses.push(Course {
                    xkkz_id: default_xkkz_id.clone(),
                    kch_id: item.kch_id.clone(),
                    kcmc: item.kcmc.clone(),
                    jxb: jxbs,
                });
            }
        }

        info!("fetch_all: {} courses", all_courses.len());
        Ok(all_courses)
    }

    /// Search a specific tab by kklxdm value
    pub async fn fetch_course_with_kklxdm(&self, q: &str, kklxdm_val: &str) -> R<Course> {
        info!("query course with kklxdm={}, q={}", kklxdm_val, q);

        #[derive(Serialize, Debug)]
        struct PDRQ<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xbm: &'a str, ccdm: &'a str, kklxdm: &'a str, xkxnm: &'a str, xkxqm: &'a str,
            jg_id: &'a str, xsbj: &'a str, mzm: &'a str, xz: &'a str,
            bh_id: &'a str, xqh_id: &'a str, zyfx_id: &'a str, xslbdm: &'a str,
            kspage: &'a str, jspage: &'a str,
            rwlx: &'a str, xklc: &'a str, xkly: &'a str, bklx_id: &'a str,
            xkkz_id: &'a str, zyh_id: &'a str, njdm_id: &'a str,
            njdm_id_1: &'a str, zyh_id_1: &'a str,
            gnjkxdnj: &'a str, bjgkczxbbjwcx: &'a str, bbhzxjxb: &'a str,
            sfkkjyxdxnxq: &'a str, kzkcgs: &'a str,
            sfkknj: &'a str, sfkkzy: &'a str, kzybkxy: &'a str,
            sfznkx: &'a str, zdkxms: &'a str, sfkxq: &'a str,
            sfkcfx: &'a str, kkbk: &'a str, kkbkdj: &'a str,
            sfkgbcx: &'a str, sfrxtgkcxd: &'a str, tykczgxdcs: &'a str,
            rlkz: &'a str, xkzgbj: &'a str, jxbzb: &'a str,
        }

        let pd = PDRQ {
            filter_list: q.into(),
            xbm: self.use_store("xbm"), ccdm: self.use_store("ccdm"), kklxdm: kklxdm_val,
            xkxnm: self.use_store("xkxnm"), xkxqm: self.use_store("xkxqm"), jg_id: self.use_store("jg_id_1"),
            xsbj: self.use_store("xsbj"), mzm: self.use_store("mzm"), xz: self.use_store("xz"),
            bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"), zyfx_id: self.use_store("zyfx_id"),
            xslbdm: self.use_store("xslbdm"), kspage: "1", jspage: "10",
            rwlx: self.use_store("rwlx"), xklc: self.use_store("xklc"), xkly: self.use_store("xkly"),
            bklx_id: self.use_store("bklx_id"), xkkz_id: self.use_store("firstXkkzId"),
            zyh_id: self.use_store("zyh_id"), njdm_id: self.use_store("njdm_id"),
            njdm_id_1: self.use_store("njdm_id_1"), zyh_id_1: self.use_store("zyh_id_1"),
            gnjkxdnj: self.use_store("gnjkxdnj"), bjgkczxbbjwcx: self.use_store("bjgkczxbbjwcx"),
            bbhzxjxb: self.use_store("bbhzxjxb"), sfkkjyxdxnxq: self.use_store("sfkkjyxdxnxq"),
            kzkcgs: self.use_store("kzkcgs"),
            sfkknj: self.use_store("sfkknj"), sfkkzy: self.use_store("sfkkzy"),
            kzybkxy: self.use_store("kzybkxy"), sfznkx: self.use_store("sfznkx"),
            zdkxms: self.use_store("zdkxms"), sfkxq: self.use_store("sfkxq"),
            sfkcfx: self.use_store("sfkcfx"), kkbk: self.use_store("kkbk"),
            kkbkdj: self.use_store("kkbkdj"), sfkgbcx: self.use_store("sfkgbcx"),
            sfrxtgkcxd: self.use_store("sfrxtgkcxd"), tykczgxdcs: self.use_store("tykczgxdcs"),
            rlkz: self.use_store("rlkz"), xkzgbj: self.use_store("xkzgbj"),
            jxbzb: self.use_store("jxbzb"),
        };

        #[derive(Deserialize, Debug)]
        struct PDRS { #[serde(rename = "tmpList")] tmp_list: Vec<PDIS2>, }
        #[derive(Deserialize, Debug)]
        struct PDIS2 { kch_id: String, #[serde(default)] kcmc: String, }

        let pdr = self.post(def::SELECT_COURSE_PART_DISPLAY_URL)?.form(&pd).send().await?.jsonr::<PDRS>().await?;
        if pdr.tmp_list.is_empty() {
            return Err(Error::JxbNotFound("tab empty"));
        }
        let kcmc = pdr.tmp_list[0].kcmc.clone();

        #[derive(Serialize, Debug)]
        struct QDRQ<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xkxqm: &'a str, xkxnm: &'a str, xkkz_id: &'a str, bklx_id: &'a str, kch_id: &'a str,
            njdm_id: &'a str, xsbj: &'a str, xz: &'a str, mzm: &'a str, kklxdm: &'a str,
            bh_id: &'a str, xqh_id: &'a str, xslbdm: &'a str, zyfx_id: &'a str,
            jg_id: &'a str, ccdm: &'a str, xbm: &'a str,
            rwlx: &'a str, xkly: &'a str, xklc: &'a str,
            zyh_id: &'a str, txbsfrl: &'a str,
            sfkkjyxdxnxq: &'a str, kzkcgs: &'a str,
            gnjkxdnj: &'a str, sfkknj: &'a str, sfkkzy: &'a str,
            kzybkxy: &'a str, sfznkx: &'a str, zdkxms: &'a str,
            sfkxq: &'a str, sfkcfx: &'a str,
            bbhzxjxb: &'a str, kkbk: &'a str, kkbkdj: &'a str,
            xkxskcgskg: &'a str, rlkz: &'a str, cdrlkz: &'a str,
            rlzlkz: &'a str, jxbzcxskg: &'a str,
            cxbj: &'a str, fxbj: &'a str,
        }

        let qd = QDRQ {
            filter_list: q.into(),
            xkxqm: self.use_store("xkxqm"), xkxnm: self.use_store("xkxnm"), xkkz_id: self.use_store("firstXkkzId"),
            bklx_id: self.use_store("bklx_id"), kch_id: &pdr.tmp_list[0].kch_id, njdm_id: self.use_store("njdm_id"),
            xsbj: self.use_store("xsbj"), xz: self.use_store("xz"), mzm: self.use_store("mzm"),
            kklxdm: kklxdm_val, bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"),
            xslbdm: self.use_store("xslbdm"), zyfx_id: self.use_store("zyfx_id"),
            jg_id: self.use_store("jg_id_1"), ccdm: self.use_store("ccdm"), xbm: self.use_store("xbm"),
            rwlx: self.use_store("rwlx"), xkly: self.use_store("xkly"), xklc: self.use_store("xklc"),
            zyh_id: self.use_store("zyh_id"), txbsfrl: self.use_store("txbsfrl"),
            sfkkjyxdxnxq: self.use_store("sfkkjyxdxnxq"), kzkcgs: self.use_store("kzkcgs"),
            gnjkxdnj: self.use_store("gnjkxdnj"), sfkknj: self.use_store("sfkknj"),
            sfkkzy: self.use_store("sfkkzy"), kzybkxy: self.use_store("kzybkxy"),
            sfznkx: self.use_store("sfznkx"), zdkxms: self.use_store("zdkxms"),
            sfkxq: self.use_store("sfkxq"), sfkcfx: self.use_store("sfkcfx"),
            bbhzxjxb: self.use_store("bbhzxjxb"), kkbk: self.use_store("kkbk"),
            kkbkdj: self.use_store("kkbkdj"), xkxskcgskg: self.use_store("xkxskcgskg"),
            rlkz: self.use_store("rlkz"), cdrlkz: self.use_store("cdrlkz"),
            rlzlkz: self.use_store("rlzlkz"), jxbzcxskg: self.use_store("jxbzcxskg"),
            cxbj: self.use_store("cxbj"), fxbj: self.use_store("fxbj"),
        };

        #[derive(Deserialize, Debug)]
        struct QDRS { do_jxb_id: String, jsxx: String, jxb_id: String, sksj: String, }

        let qdr = self.post(def::SELECT_COURSE_QUERY_DO_WITH_COURSE_ID_URL)?.form(&qd).send().await?.jsonr::<Vec<QDRS>>().await?;

        let mut course = Course {
            xkkz_id: self.stores.get("firstXkkzId").ok_or(Error::Missing("[firstXkkzId]".into()))?.into(),
            kch_id: pdr.tmp_list[0].kch_id.clone(), kcmc, jxb: vec![],
        };
        for item in qdr {
            course.jxb.push(Jxb { jxb_id: item.jxb_id, do_id: item.do_jxb_id, jsxx: item.jsxx, sksj: item.sksj, jxbmc: String::new() });
        }
        info!("fetch course with kklxdm success"); Ok(course)
    }


    /// Search a specific tab by xkkz_id value
    pub async fn fetch_course_with_xkkz_id(&self, q: &str, xkkz_id_val: &str) -> R<Course> {
        info!("query course with xkkz_id={}, q={}", xkkz_id_val, q);

        #[derive(Serialize, Debug)]
        struct PDRQ3<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xbm: &'a str, ccdm: &'a str, kklxdm: &'a str, xkxnm: &'a str, xkxqm: &'a str,
            jg_id: &'a str, xsbj: &'a str, mzm: &'a str, xz: &'a str,
            bh_id: &'a str, xqh_id: &'a str, zyfx_id: &'a str, xslbdm: &'a str,
            kspage: &'a str, jspage: &'a str,
            rwlx: &'a str, xklc: &'a str, xkly: &'a str, bklx_id: &'a str,
            xkkz_id: &'a str, zyh_id: &'a str, njdm_id: &'a str,
            njdm_id_1: &'a str, zyh_id_1: &'a str,
            gnjkxdnj: &'a str, bjgkczxbbjwcx: &'a str, bbhzxjxb: &'a str,
            sfkkjyxdxnxq: &'a str, kzkcgs: &'a str,
            sfkknj: &'a str, sfkkzy: &'a str, kzybkxy: &'a str,
            sfznkx: &'a str, zdkxms: &'a str, sfkxq: &'a str,
            sfkcfx: &'a str, kkbk: &'a str, kkbkdj: &'a str,
            sfkgbcx: &'a str, sfrxtgkcxd: &'a str, tykczgxdcs: &'a str,
            rlkz: &'a str, xkzgbj: &'a str, jxbzb: &'a str,
        }

        let pd = PDRQ3 {
            filter_list: q.into(),
            xbm: self.use_store("xbm"), ccdm: self.use_store("ccdm"), kklxdm: self.use_store("firstKklxdm"),
            xkxnm: self.use_store("xkxnm"), xkxqm: self.use_store("xkxqm"), jg_id: self.use_store("jg_id_1"),
            xsbj: self.use_store("xsbj"), mzm: self.use_store("mzm"), xz: self.use_store("xz"),
            bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"), zyfx_id: self.use_store("zyfx_id"),
            xslbdm: self.use_store("xslbdm"), kspage: "1", jspage: "10",
            rwlx: self.use_store("rwlx"), xklc: self.use_store("xklc"), xkly: self.use_store("xkly"),
            bklx_id: self.use_store("bklx_id"), xkkz_id: self.use_store("firstXkkzId"),
            zyh_id: self.use_store("zyh_id"), njdm_id: self.use_store("njdm_id"),
            njdm_id_1: self.use_store("njdm_id_1"), zyh_id_1: self.use_store("zyh_id_1"),
            gnjkxdnj: self.use_store("gnjkxdnj"), bjgkczxbbjwcx: self.use_store("bjgkczxbbjwcx"),
            bbhzxjxb: self.use_store("bbhzxjxb"), sfkkjyxdxnxq: self.use_store("sfkkjyxdxnxq"),
            kzkcgs: self.use_store("kzkcgs"),
            sfkknj: self.use_store("sfkknj"), sfkkzy: self.use_store("sfkkzy"),
            kzybkxy: self.use_store("kzybkxy"), sfznkx: self.use_store("sfznkx"),
            zdkxms: self.use_store("zdkxms"), sfkxq: self.use_store("sfkxq"),
            sfkcfx: self.use_store("sfkcfx"), kkbk: self.use_store("kkbk"),
            kkbkdj: self.use_store("kkbkdj"), sfkgbcx: self.use_store("sfkgbcx"),
            sfrxtgkcxd: self.use_store("sfrxtgkcxd"), tykczgxdcs: self.use_store("tykczgxdcs"),
            rlkz: self.use_store("rlkz"), xkzgbj: self.use_store("xkzgbj"),
            jxbzb: self.use_store("jxbzb"),
        };

        #[derive(Deserialize, Debug)]
        struct PDRS3 { #[serde(rename = "tmpList")] tmp_list: Vec<PDIS3>, }
        #[derive(Deserialize, Debug)]
        struct PDIS3 { kch_id: String, #[serde(default)] kcmc: String, }

        let pdr = self.post(def::SELECT_COURSE_PART_DISPLAY_URL)?.form(&pd).send().await?.jsonr::<PDRS3>().await?;
        if pdr.tmp_list.is_empty() {
            return Err(Error::JxbNotFound("tab empty"));
        }
        let kcmc = pdr.tmp_list[0].kcmc.clone();

        #[derive(Serialize, Debug)]
        struct QDRQ3<'a> {
            #[serde(rename = "filter_list[0]")] filter_list: &'a str,
            xkxqm: &'a str, xkxnm: &'a str, xkkz_id: &'a str, bklx_id: &'a str, kch_id: &'a str,
            njdm_id: &'a str, xsbj: &'a str, xz: &'a str, mzm: &'a str, kklxdm: &'a str,
            bh_id: &'a str, xqh_id: &'a str, xslbdm: &'a str, zyfx_id: &'a str,
            jg_id: &'a str, ccdm: &'a str, xbm: &'a str,
            rwlx: &'a str, xkly: &'a str, xklc: &'a str,
            zyh_id: &'a str, txbsfrl: &'a str,
            sfkkjyxdxnxq: &'a str, kzkcgs: &'a str,
            gnjkxdnj: &'a str, sfkknj: &'a str, sfkkzy: &'a str,
            kzybkxy: &'a str, sfznkx: &'a str, zdkxms: &'a str,
            sfkxq: &'a str, sfkcfx: &'a str,
            bbhzxjxb: &'a str, kkbk: &'a str, kkbkdj: &'a str,
            xkxskcgskg: &'a str, rlkz: &'a str, cdrlkz: &'a str,
            rlzlkz: &'a str, jxbzcxskg: &'a str,
            cxbj: &'a str, fxbj: &'a str,
        }

        let qd = QDRQ3 {
            filter_list: q.into(),
            xkxqm: self.use_store("xkxqm"), xkxnm: self.use_store("xkxnm"), xkkz_id: xkkz_id_val,
            bklx_id: self.use_store("bklx_id"), kch_id: &pdr.tmp_list[0].kch_id, njdm_id: self.use_store("njdm_id"),
            xsbj: self.use_store("xsbj"), xz: self.use_store("xz"), mzm: self.use_store("mzm"),
            kklxdm: self.use_store("firstKklxdm"), bh_id: self.use_store("bh_id"), xqh_id: self.use_store("xqh_id"),
            xslbdm: self.use_store("xslbdm"), zyfx_id: self.use_store("zyfx_id"),
            jg_id: self.use_store("jg_id_1"), ccdm: self.use_store("ccdm"), xbm: self.use_store("xbm"),
            rwlx: self.use_store("rwlx"), xkly: self.use_store("xkly"), xklc: self.use_store("xklc"),
            zyh_id: self.use_store("zyh_id"), txbsfrl: self.use_store("txbsfrl"),
            sfkkjyxdxnxq: self.use_store("sfkkjyxdxnxq"), kzkcgs: self.use_store("kzkcgs"),
            gnjkxdnj: self.use_store("gnjkxdnj"), sfkknj: self.use_store("sfkknj"),
            sfkkzy: self.use_store("sfkkzy"), kzybkxy: self.use_store("kzybkxy"),
            sfznkx: self.use_store("sfznkx"), zdkxms: self.use_store("zdkxms"),
            sfkxq: self.use_store("sfkxq"), sfkcfx: self.use_store("sfkcfx"),
            bbhzxjxb: self.use_store("bbhzxjxb"), kkbk: self.use_store("kkbk"),
            kkbkdj: self.use_store("kkbkdj"), xkxskcgskg: self.use_store("xkxskcgskg"),
            rlkz: self.use_store("rlkz"), cdrlkz: self.use_store("cdrlkz"),
            rlzlkz: self.use_store("rlzlkz"), jxbzcxskg: self.use_store("jxbzcxskg"),
            cxbj: self.use_store("cxbj"), fxbj: self.use_store("fxbj"),
        };

        #[derive(Deserialize, Debug)]
        struct QDRS3 { do_jxb_id: String, jsxx: String, jxb_id: String, sksj: String, }

        let qdr = self.post(def::SELECT_COURSE_QUERY_DO_WITH_COURSE_ID_URL)?.form(&qd).send().await?.jsonr::<Vec<QDRS3>>().await?;

        let mut course = Course {
            xkkz_id: xkkz_id_val.into(),
            kch_id: pdr.tmp_list[0].kch_id.clone(), kcmc, jxb: vec![],
        };
        for item in qdr {
            course.jxb.push(Jxb { jxb_id: item.jxb_id, do_id: item.do_jxb_id, jsxx: item.jsxx, sksj: item.sksj, jxbmc: String::new() });
        }
        info!("fetch course with xkkz_id success"); Ok(course)
    }


    /// Switch to a different course tab by xkkz_id, updating stores
    pub async fn switch_tab(&mut self, xkkz_id_val: &str) -> R<()> {
        info!("switching to tab xkkz_id={}", xkkz_id_val);

        #[derive(Serialize, Debug)]
        struct DisplayRequestData<'a> {
            xkkz_id: &'a str,
            xszxzt: &'a str,
            kspage: &'a str,
        }

        let display_data = DisplayRequestData {
            xkkz_id: xkkz_id_val,
            xszxzt: "1",
            kspage: "1",
        };

        let display_doc = self
            .post(def::SELECT_COURSE_DISPLAY_URL)?
            .form(&display_data)
            .send()
            .await?
            .doc()
            .await?;

        for item in display_doc.select(&def::S_INPUT_HIDDENT) {
            let name = item.attr("name").unwrap_or("");
            let value = item.attr("value").unwrap_or("");
            self.store(name, value);
        }

        info!("switched tab OK, kklxdm={}", self.use_store("firstKklxdm"));
        Ok(())
    }

}
