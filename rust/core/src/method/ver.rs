use crate::{
    Client, def,
    error::R,
    utils::{ToHtml, ToResponse, UseVer},
};

impl Client {
    pub async fn ver(&self) -> R<Option<String>> {
        Ok(self
            .get(def::LOGIN_URL)?
            .send_r().await?
            ._doc()
            .await?
            .use_ver())
    }
}
