use serde::{Deserialize, Serialize};

use crate::{
    Client, def,
    error::{Error, R},
    utils::{
        ToJson, ToResponse,
        macros::{debug, error, info, trace, warn},
    },
};

impl Client {
    /// 子教学班选课（部分课程需要先选子班）— 通用版
    pub async fn select_course_subclass(
        &self,
        course_id: &str,
        course_do_id: &str,
        kcmc: &str,
        xkkz_id: &str,
    ) -> R<SelectCourseResponse> {
        info!("执行子班选课");

        let xh = self
            .stores
            .get("xh_id")
            .ok_or(Error::MissingField("xh_id"))?;

        if xh.len() < 8 {
            error!("xh_id {} 无法提取选课参数", xh);
            return Err(Error::InvalidXhId);
        }

        #[derive(Serialize, Debug)]
        struct SelectSubclassData<'a> {
            jxb_ids: &'a str,
            kch_id: &'a str,
            kcmc: &'a str,
            rwlx: &'a str,
            rlkz: &'a str,
            cdrlkz: &'a str,
            rlzlkz: &'a str,
            sxbj: &'a str,
            xxkbj: &'a str,
            qz: &'a str,
            cxbj: &'a str,
            xkkz_id: &'a str,
            njdm_id: &'a str,
            zyh_id: &'a str,
            kklxdm: &'a str,
            xklc: &'a str,
            xkxnm: &'a str,
            xkxqm: &'a str,
            jcxx_id: &'a str,
        }

        let zyh = self.use_store("zyh_id");
        let njdm = self.use_store("njdm_id");
        let zyh_id_val: &str = if !zyh.is_empty() { zyh } else { &xh[4..8] };
        let njdm_id_val: &str = if !njdm.is_empty() { njdm } else { &xh[0..4] };

        trace!("发送请求子班选课");

        let res = self
            .post(def::SELECT_COURSE_SUBCLASS_URL)?
            .form(&SelectSubclassData {
                jxb_ids: course_do_id,
                kch_id: course_id,
                kcmc,
                rwlx: "2",
                rlkz: "0",
                cdrlkz: "0",
                rlzlkz: "1",
                sxbj: "1",
                xxkbj: "0",
                qz: "0",
                cxbj: "0",
                xkkz_id,
                njdm_id: njdm_id_val,
                zyh_id: zyh_id_val,
                kklxdm: self.use_store("firstKklxdm"),
                xklc: "2",
                xkxnm: self.use_store("xkxnm"),
                xkxqm: self.use_store("xkxqm"),
                jcxx_id: "",
            })
            .send_r().await?;

        let res = res.jsonr::<SelectCourseResponse>().await?.normalized();

        if res.is_success() {
            info!("子班选课成功");
        } else {
            warn!("子班选课失败: {}", res.msg().unwrap_or("未知错误"));
        }

        Ok(res)
    }

    /// 子教学班选课 V2 — 丽江师范专用端点 (zzxkyzb_xkZyZzxkYzbZjxb)
    pub async fn select_course_subclass_v2(
        &self,
        jxb_id: &str,
        do_jxb_id: &str,
        jxbzls: &str,
    ) -> R<SelectCourseResponse> {
        info!("执行子班选课V2");

        #[derive(Serialize, Debug)]
        struct SubV2Data<'a> {
            jxb_id: &'a str,
            do_jxb_id: &'a str,
            jxbzls: &'a str,
            rwlx: &'a str,
            zcongbj: &'a str,
            syqz: &'a str,
            rlkz: &'a str,
            fxbj: &'a str,
            cxbj: &'a str,
            rlzlkz: &'a str,
            cdrlkz: &'a str,
        }

        let res = self
            .post(def::SELECT_COURSE_SUBCLASS_V2_URL)?
            .header("Accept", "text/html, */*; q=0.01")
            .form(&SubV2Data {
                jxb_id,
                do_jxb_id,
                jxbzls,
                rwlx: "2",
                zcongbj: "0",
                syqz: "100",
                rlkz: "0",
                fxbj: "0",
                cxbj: "0",
                rlzlkz: "1",
                cdrlkz: "0",
            })
            .send_r().await?;

        let body = res.text().await?;
        info!("子班V2响应: {}", &body[..body.len().min(500)]);

        // HTML response: check for success indicators
        let success = body.contains("成功") || body.contains("success");
        let flag = if success { "1" } else { "0" };
        let msg: Option<String> = if success {
            None
        } else if body.contains("子教学班") {
            Some("该教学班有子教学班未选".into())
        } else if body.contains("不在选课时间") {
            Some("不在选课时间内".into())
        } else if body.contains("未开放") {
            Some("当前未开放选课".into())
        } else {
            Some(format!("BODY:{}", &body[..body.len().min(5000)]))
        };

        let res = SelectCourseResponse { flag: flag.into(), msg }.normalized();

        if res.is_success() {
            info!("子班V2选课成功");
        } else {
            warn!("子班V2选课失败: {}", res.msg().unwrap_or("未知错误"));
        }

        Ok(res)
    }

    /// 获取子教学班 ID 列表（从子班展示页 HTML 中解析 do_jxb_id）
    pub async fn fetch_subclass_ids(&self, do_jxb_id: &str) -> R<Vec<String>> {
        info!("获取子教学班列表");

        #[derive(Serialize, Debug)]
        struct SubDisplayData<'a> {
            jxb_id: &'a str,
            jxbzls: &'a str,
            xkly: &'a str,
            cdrlkz: &'a str,
            rlkz: &'a str,
            rlzlkz: &'a str,
            rwlx: &'a str,
            syqz: &'a str,
            xkxnm: &'a str,
            xkxqm: &'a str,
            zyfx_id: &'a str,
            bh_id: &'a str,
            zyh_id: &'a str,
            njdm_id: &'a str,
            xh_id: &'a str,
            kklxdm: &'a str,
            xklc: &'a str,
        }

        let xh = self.stores.get("xh_id").ok_or(Error::MissingField("xh_id"))?;
        let zyh2 = self.use_store("zyh_id");
        let njdm2 = self.use_store("njdm_id");
        let zyh_id_v2: &str = if !zyh2.is_empty() { zyh2 } else { &xh[4..8] };
        let njdm_id_v2: &str = if !njdm2.is_empty() { njdm2 } else { &xh[0..4] };

        let res = self
            .post(def::DISPLAY_SUBCLASS_URL)?
            .header("Accept", "text/html, */*; q=0.01")
            .form(&SubDisplayData {
                jxb_id: do_jxb_id,
                jxbzls: "1",
                xkly: "0",
                cdrlkz: "0",
                rlkz: "0",
                rlzlkz: "1",
                rwlx: "2",
                syqz: "100",
                xkxnm: self.use_store("xkxnm"),
                xkxqm: self.use_store("xkxqm"),
                zyfx_id: self.use_store("zyfx_id"),
                bh_id: self.use_store("bh_id"),
                zyh_id: zyh_id_v2,
                njdm_id: njdm_id_v2,
                xh_id: xh,
                kklxdm: self.use_store("firstKklxdm"),
                xklc: "2",
            })
            .send_r().await?;

        let body = res.text().await?;
        trace!("子班列表响应: {}", &body[..body.len().min(300)]);

        // Parse do_jxb_id values from the HTML
        let mut ids = Vec::new();
        for part in body.split("do_jxb_id") {
            if let Some(rest) = part.strip_prefix("=") {
                let id = rest.split(&['&', '"', '\''][..]).next().unwrap_or("");
                if id.len() > 30 && !ids.contains(&id.to_string()) {
                    ids.push(id.to_string());
                }
            }
            if let Some(rest) = part.strip_prefix("\":\"") {
                let id = rest.split('"').next().unwrap_or("");
                if id.len() > 30 && !ids.contains(&id.to_string()) {
                    ids.push(id.to_string());
                }
            }
        }
        info!("找到 {} 个子班", ids.len());
        Ok(ids)
    }

    /// 选课接口
    pub async fn select_course(
        &self,
        course_id: &str,
        course_do_id: &str,
    ) -> R<SelectCourseResponse> {
        info!("执行选课");

        let xh = self
            .stores
            .get("xh_id")
            .ok_or(Error::MissingField("xh_id"))?;

        if xh.len() < 8 {
            error!("xh_id {} 无法提取选课参数", xh);
            return Err(Error::InvalidXhId);
        }

        #[derive(Serialize, Debug)]
        struct SelectCourseData<'a> {
            // 选课需要的参数
            jxb_ids: &'a str,
            kch_id: &'a str,
            qz: &'a str, // 0 定值
            // <input type="hidden" name="njdm_id" id="njdm_id" value="">
            njdm_id: &'a str,
            // <input type="hidden" name="zyh_id" id="zyh_id" value="">
            zyh_id: &'a str,
        }

        // 山青等学校 zyh_id 是 32 位哈希，需从 stores 读取；否则回退按学号截取
        let zyh3 = self.use_store("zyh_id");
        let njdm3 = self.use_store("njdm_id");
        let zyh_id_v3: &str = if !zyh3.is_empty() { zyh3 } else { &xh[4..8] };
        let njdm_id_v3: &str = if !njdm3.is_empty() { njdm3 } else { &xh[0..4] };

        trace!("发送请求选课");

        let res = self
            .post(def::SELECT_COURSE_URL)?
            .form(&SelectCourseData {
                jxb_ids: course_do_id,
                kch_id: course_id,
                qz: "0",
                njdm_id: njdm_id_v3,
                zyh_id: zyh_id_v3,
            })
            .send_r().await?;

        let res = res.jsonr::<SelectCourseResponse>().await?.normalized();

        if res.is_success() {
            info!("选课成功");
        } else {
            warn!("选课失败: {}", res.msg().unwrap_or("未知错误"));
        }

        debug!("选课结果: {:?}", res);

        Ok(res)
    }
}

/// { flag: "1", msg: None }
///
/// { flag: "0", msg: Some("对不起，当前未开放选课！") }
///
/// { flag: "0", msg: Some("选课频率过高，请稍后重试！") }
///
/// { flag: "0", msg: Some("一门课程只能选一个教学班，不可再选！") }
///
/// { flag: "0", msg: Some("超过体育分项本学期本专业最高选课门次限制，不可选！") }
///
/// { flag: "0", msg: Some("超过通识选修课本学期本专业最高选课门次限制，不可选！") }
#[cfg_attr(
    feature = "__pyo3",
    cfg_attr(test, pyo3_stub_gen::derive::gen_stub_pyclass),
    pyo3::pyclass(get_all)
)]
#[derive(Deserialize, Debug)]
pub struct SelectCourseResponse {
    pub flag: String,
    pub msg: Option<String>,
}

impl SelectCourseResponse {
    pub fn is_success(&self) -> bool {
        self.flag == "1"
    }

    pub fn msg(&self) -> Option<&str> {
        self.msg.as_deref()
    }

    /// 部分学校（如黄冈师范）课程已满时返回 flag="-1"、msg="0,jxb_id,已选人数,"，
    /// 把这种原始数组段翻译成友好提示，便于日志与 UI 展示。
    pub fn normalized(mut self) -> Self {
        if self.flag == "-1" {
            if let Some(m) = &self.msg {
                let parts: Vec<&str> = m.split(',').collect();
                if parts.len() >= 3
                    && !parts[2].is_empty()
                    && parts[2].chars().all(|c| c.is_ascii_digit())
                {
                    self.msg = Some(format!("该教学班已无余量，不可选！(已选 {} 人)", parts[2]));
                }
            }
        }
        self
    }
}
