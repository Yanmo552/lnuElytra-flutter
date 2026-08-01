use tokio::runtime::Runtime;

use crate::{Course, SelectCourseResponse, error::R};

pub struct Client {
    client: crate::Client,
    runtime: Runtime,
}

impl Client {
    pub fn new() -> Self {
        Self {
            client: crate::Client::new(),
            runtime: Runtime::new().unwrap(),
        }
    }

    pub fn new_with_base(backend: &str) -> R<Self> {
        Ok(Self {
            client: crate::Client::new_with_base(backend.parse()?),
            runtime: Runtime::new().unwrap(),
        })
    }

    pub fn login(&mut self, username: &str, password: &str) -> R<String> {
        self.runtime.block_on(self.client.login(username, password))
    }

    pub fn check_login(&self) -> R<String> {
        self.runtime.block_on(self.client.check_login())
    }

    pub fn init(&mut self) -> R {
        self.runtime.block_on(self.client.init())
    }

    pub fn switch_tab(&mut self, xkkz_id: &str) -> R {
        self.runtime.block_on(self.client.switch_tab(xkkz_id))
    }

    pub fn fetch_course(&self, q: &str) -> R<Course> {
        self.runtime.block_on(self.client.fetch_courses(q))
    }

    pub fn fetch_course_with_xkkz_id(&self, q: &str, xkkz_id: &str) -> R<Course> {
        self.runtime
            .block_on(self.client.fetch_course_with_xkkz_id(q, xkkz_id))
    }

    pub fn fetch_course_with_kklxdm(&self, q: &str, kklxdm: &str) -> R<Course> {
        self.runtime
            .block_on(self.client.fetch_course_with_kklxdm(q, kklxdm))
    }

    pub fn fetch_courses_all(&self, q: &str) -> R<Vec<Course>> {
        self.runtime.block_on(self.client.fetch_courses_all(q))
    }

    pub fn get_all_xkkz_ids(&self) -> Vec<String> {
        self.client.get_all_xkkz_ids()
    }

    pub fn init_done(&self) -> bool {
        self.client.init_done()
    }

    pub fn check_open(&self) -> bool {
        self.runtime.block_on(self.client.check_open())
    }

    pub fn select_course(&self, course_id: &str, course_do_id: &str) -> R<SelectCourseResponse> {
        self.runtime
            .block_on(self.client.select_course(course_id, course_do_id))
    }

    pub fn select_course_subclass(
        &self,
        course_id: &str,
        course_do_id: &str,
        kcmc: &str,
        xkkz_id: &str,
    ) -> R<SelectCourseResponse> {
        self.runtime.block_on(self.client.select_course_subclass(
            course_id,
            course_do_id,
            kcmc,
            xkkz_id,
        ))
    }

    pub fn select_course_subclass_v2(
        &self,
        jxb_id: &str,
        do_jxb_id: &str,
        jxbzls: &str,
    ) -> R<SelectCourseResponse> {
        self.runtime.block_on(
            self.client
                .select_course_subclass_v2(jxb_id, do_jxb_id, jxbzls),
        )
    }

    pub fn fetch_subclass_ids(&self, do_jxb_id: &str) -> R<Vec<String>> {
        self.runtime.block_on(self.client.fetch_subclass_ids(do_jxb_id))
    }

    pub fn ver(&self) -> R<Option<String>> {
        self.runtime.block_on(self.client.ver())
    }
}

#[cfg(feature = "reqwest_cookie_store")]
impl Client {
    pub fn cookies(&self) -> Option<String> {
        self.client.cookies()
    }

    pub fn insert_cookie(&self, cookie: &str) -> R {
        self.client.insert_cookie(cookie)
    }

    pub fn insert_cookies(&self, cookies: &str) -> R {
        self.client.insert_cookies(cookies)
    }

    pub fn clear_cookie(&self) {
        self.client.clear_cookie();
    }
}

impl Course {
    pub fn try_select_0_blocking(&self, client: &Client) -> R<SelectCourseResponse> {
        client.runtime.block_on(self.try_select_0(&client.client))
    }

    pub fn try_select_by_time_blocking(&self, client: &Client, q: &str) -> R<SelectCourseResponse> {
        client
            .runtime
            .block_on(self.try_select_by_time(&client.client, q))
    }
}
