use serde::Serialize;

use crate::{
    Client, def,
    error::{Error, R},
    utils::{ToHtml, macros::info},
};

impl Client {
    /// 获取指定kklxdm对应的xkkz_id
    pub(crate) fn get_xkkz_id_for(&self, kklxdm: &str) -> Option<&String> {
        self.stores.get(&format!("xkkz_id_for_{kklxdm}"))
    }

    /// 获取所有已发现的kklxdm值
    pub(crate) fn get_all_kklxdm(&self) -> Vec<String> {
        let mut result: Vec<String> = self.stores.keys()
            .filter(|k| k.starts_with("xkkz_id_for_"))
            .map(|k| k.trim_start_matches("xkkz_id_for_").to_string())
            .collect();
        // 确保默认的也在里面
        let default = self.use_store("firstKklxdm").clone();
        if !default.is_empty() && !result.contains(&default) {
            result.push(default);
        }
        result
    }

    /// 获取选课基本参数，每次选课只需要执行一次
    pub async fn init(&mut self) -> R {
        info!("正在获取选课基本参数...");

        let index_doc = self
            .get(def::SELECT_COURSE_HTML_URL)?
            .send()
            .await?
            .doc()
            .await?;

        for item in index_doc.select(&def::S_INPUT_HIDDENT) {
            let name = item.attr("name").unwrap_or("");
            let value = item.attr("value").unwrap_or("");
            self.store(name, value);
        }

        #[derive(Serialize, Debug)]
        struct DisplayRequestData<'a> {
            xkkz_id: &'a str,
            xszxzt: &'a str,
            kspage: &'a str,
        }

        let display_data = DisplayRequestData {
            xkkz_id: self.stores.get("firstXkkzId").ok_or(Error::NotyetStarted)?,
            xszxzt: "1".into(),
            kspage: "1".into(),
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

        // 解析 onclick="queryCourse(this,'kklxdm','xkkz_id',...)" 提取映射
        let html_str = index_doc.html();
        let mut pos = 0;
        while let Some(start) = html_str[pos..].find("queryCourse(this,") {
            let abs_start = pos + start;
            let snippet = &html_str[abs_start..];
            // 提取引号内的参数
            let parts: Vec<&str> = snippet.split('\'').collect();
            if parts.len() >= 5 {
                let kklxdm = parts[1];
                let xkkz_id = parts[3];
                if kklxdm.len() <= 3 && xkkz_id.len() == 32 {
                    self.store(&format!("xkkz_id_for_{kklxdm}"), xkkz_id);
                    info!("found tab: kklxdm={kklxdm} xkkz_id={xkkz_id}");
                }
            }
            pos = abs_start + 20;
        }

        // Collect xkkz_id values using CSS selector
        let xkkz_selector = scraper::Selector::parse("input[name=xkkz_id]").unwrap();
        let mut xids: Vec<String> = Vec::new();
        let mut collect = |doc: &scraper::Html| {
            for item in doc.select(&xkkz_selector) {
                if let Some(val) = item.attr("value") {
                    let v = val.to_string();
                    if !v.is_empty() && !xids.contains(&v) {
                        xids.push(v);
                    }
                }
            }
        };
        collect(&display_doc);
        collect(&index_doc);
        info!("discovered {} xkkz_id values", xids.len());
        // Store as xkkz_id_list_0, xkkz_id_list_1, ...
        for (i, xid) in xids.iter().enumerate() {
            self.store(&format!("xkkz_id_list_{i}"), xid);
        }
        self.store("xkkz_id_count", &xids.len().to_string());
        info!("discovered {} xkkz_id tabs", xids.len());

        info!("选课基本参数获取成功");

        self._init_done = true;

        Ok(())
    }

    /// Get all discovered xkkz_id values
    pub fn get_all_xkkz_ids(&self) -> Vec<String> {
        let count_str = self.use_store("xkkz_id_count");
        let count: usize = count_str.parse().unwrap_or(0);
        let mut result = Vec::new();
        for i in 0..count {
            let key = format!("xkkz_id_list_{i}");
            if let Some(val) = self.stores.get(&key) {
                result.push(val.clone());
            }
        }
        result
    }
}
